package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"time"

	v1 "k8s.io/api/core/v1"
	metaV1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	ctrl "sigs.k8s.io/controller-runtime"

	"github.com/gocql/gocql"
)

var Logger = slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))

var isHealth = false

type HttpClient struct {
	client   http.Client
	user     string
	password string
}

type Server struct {
	endpoint        string
	errorsCount     int
	retryCount      int
	storage         string
	servicePort     int
	shutdownTimeout time.Duration
	tlsEnabled      bool
	opensearch      *HttpClient
	cassandra       *gocql.Session
	keyspace        string
	testTable       string
}

const (
	cassandra string = "cassandra"
)

func main() {
	slog.SetDefault(Logger)
	slog.Info("Starting the service")
	s := initServer()
	host := "0.0.0.0:" + strconv.Itoa(s.servicePort)
	mux := http.NewServeMux()
	mux.HandleFunc("/health", s.readinessProbe)
	mux.HandleFunc("/livez", s.livenessProbe)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	server := &http.Server{
		Addr:    host,
		Handler: mux,
	}

	go func() {
		slog.Info(fmt.Sprintf("The service is listening on 0.0.0.0:%d", s.servicePort))
		if err := server.ListenAndServe(); err != nil {
			if err != http.ErrServerClosed {
				slog.Error(err.Error())
				os.Exit(1)
			}
		}
	}()

	go func() {
		slog.Info("Readiness probe process is starting")
		for {
			isHealth = s.isHealth()
			slog.Info("Sleep for 10 sec and try again")
			time.Sleep(10 * time.Second)
		}
	}()

	<-ctx.Done()

	stop()
	slog.Info("Shutting down gracefully, press Ctrl+C again to force")

	timeoutCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	go func() {
		if err := server.Shutdown(timeoutCtx); err != nil {
			slog.Error(err.Error())
			os.Exit(1)
		}
		os.Exit(0)
	}()
}

func initServer() *Server {
	// Probe service parameters
	servicePort := flag.Int("servicePort", 8080, "The number of port for running service")
	shutdownTimeout := flag.Int("shutdownTimeout", 5, "The number of seconds for graceful shutdown before connections are cancelled")

	// Common parameters
	storage := flag.String("storage", "cassandra", "The type of storage for checking probe")
	host := flag.String("host", "", "The host for probe")
	port := flag.Int("port", 0, "The port for probe")

	errors := flag.Int("errors", 3, "The number of allowed errors for checking probe")
	retries := flag.Int("retries", 3, "The number of retries for checking probe")
	timeout := flag.Int("timeout", 5, "The number of seconds for failing probe by timeout")

	tlsEnabled := flag.Bool("tlsEnabled", false, "Enabling TLS for connection to the storage")
	insecureSkipVerify := flag.Bool("insecureSkipVerify", false, "Disabling host verification for TLS")

	// Parameters to fetch information from the Secret
	namespace := flag.String("namespace", "tracing", "Namespace for service with probe")
	authSecretName := flag.String("authSecretName", "", "Secret name with username and password values")
	ca := flag.String("caPath", "", "The path for ca-cert.pem file")
	crt := flag.String("crtPath", "", "The path for client-cert.pem file")
	key := flag.String("keyPath", "", "The path for client-key.pem file")

	// Cassandra specific parameters
	keyspace := flag.String("keyspace", "jaeger", "Keyspace for the Cassandra database")
	datacenter := flag.String("datacenter", "datacenter1", "Datacenter for the Cassandra database")
	testtable := flag.String("testtable", "service_names", "Table name for getting test data from the Cassandra database")

	var user, pass string
	flag.Parse()
	if *host == "" {
		slog.Error("Missing required argument -host")
		os.Exit(1)
	} else if *authSecretName == "" {
		slog.Error("Missing required argument -authSecretName")
		os.Exit(1)
	} else if *tlsEnabled {
		if !*insecureSkipVerify && (*ca == "" || *crt == "" || *key == "") {
			slog.Error("Missing one of the required arguments -caPath, -crtPath, -keyPath")
			os.Exit(1)
		}
	}
	secret := readSecret(*namespace, *authSecretName)
	user = readFromSecret(secret, v1.BasicAuthUsernameKey)
	pass = readFromSecret(secret, v1.BasicAuthPasswordKey)
	endpoint := *host
	if *port != 0 {
		endpoint += ":" + strconv.Itoa(*port)
	}
	var opensearchClient *HttpClient
	var cassandraClient *gocql.Session
	if *storage == "opensearch" {
		opensearchClient = createHttpClient(user, pass, *tlsEnabled, *ca, *crt, *key, *insecureSkipVerify, time.Duration(*timeout))
	} else {
		cassandraClient = createCassandraClient(*host, *port, user, pass, *tlsEnabled, *ca, *crt, *key, *insecureSkipVerify, time.Duration(*timeout), *errors, *datacenter, *keyspace)
	}
	return &Server{
		endpoint:        endpoint,
		tlsEnabled:      *tlsEnabled,
		retryCount:      *retries,
		errorsCount:     *errors,
		storage:         *storage,
		servicePort:     *servicePort,
		shutdownTimeout: time.Duration(*shutdownTimeout),
		opensearch:      opensearchClient,
		cassandra:       cassandraClient,
		testTable:       *testtable,
		keyspace:        *keyspace,
	}
}

func readSecret(namespace string, secretName string) *v1.Secret {
	config, err := ctrl.GetConfig()
	if err != nil {
		slog.Error(err.Error())
	}
	k8sClient, err := kubernetes.NewForConfig(config)
	if err != nil {
		slog.Error(err.Error())
	}
	secret, err := k8sClient.CoreV1().Secrets(namespace).Get(context.TODO(), secretName, metaV1.GetOptions{})
	if err != nil {
		slog.Error(err.Error())
	}
	return secret
}

func readFromSecret(secret *v1.Secret, key string) string {
	value := string(secret.Data[key])
	if value == "" {
		slog.Error(fmt.Sprintf("Can't read the field '%s' from the secret '%s/%s'", key, secret.Namespace, secret.Name))
		os.Exit(1)
	}
	return value
}

func createCassandraClient(host string, port int, user string, password string, tlsEnabled bool, ca string, crt string, key string, verification bool, timeout time.Duration, errorsCount int, datacenter string, keyspace string) *gocql.Session {
	cluster := gocql.NewCluster(host)
	cluster.Port = port
	cluster.Keyspace = keyspace
	cluster.ConnectTimeout = time.Second * timeout
	cluster.NumConns = 1
	if tlsEnabled {
		if verification {
			cluster.SslOpts = &gocql.SslOptions{
				EnableHostVerification: !verification,
			}
		} else {
			cluster.SslOpts = &gocql.SslOptions{
				CertPath:               crt,
				CaPath:                 ca,
				KeyPath:                key,
				EnableHostVerification: !verification,
			}
		}
	}
	cluster.Authenticator = gocql.PasswordAuthenticator{
		Username: user,
		Password: password,
	}
	cluster.PoolConfig.HostSelectionPolicy = gocql.DCAwareRoundRobinPolicy(datacenter)
	cluster.ProtoVersion = 4
	cluster.Consistency = gocql.Quorum
	cluster.DisableInitialHostLookup = true
	session, err := createSessionWithRetry(cluster, errorsCount, time.Second)
	if err != nil {
		slog.Error(fmt.Sprintf("Can't create session: %s", err.Error()))
	}
	return session
}

func createHttpClient(user string, password string, tlsEnabled bool, ca string, crt string, key string, verification bool, timeout time.Duration) *HttpClient {
	client := http.Client{Timeout: timeout * time.Second}
	if tlsEnabled {
		tlsConfig := &tls.Config{
			InsecureSkipVerify: verification,
		}
		if !verification {
			// load tls certificates
			clientTLSCert, err := tls.LoadX509KeyPair(crt, key)
			if err != nil {
				slog.Error(fmt.Sprintf("Error loading certificate and key files: %v", err))
			}
			// Configure the client to trust TLS server certs issued by a CA.
			certPool, err := x509.SystemCertPool()
			if err != nil {
				slog.Error(err.Error())
			}
			if caCertPEM, err := os.ReadFile(ca); err != nil {
				slog.Error(err.Error())
			} else if ok := certPool.AppendCertsFromPEM(caCertPEM); !ok {
				slog.Error("Invalid cert in CA PEM")
			}
			tlsConfig = &tls.Config{
				RootCAs:            certPool,
				Certificates:       []tls.Certificate{clientTLSCert},
				InsecureSkipVerify: verification,
			}
		}
		client.Transport = &http.Transport{
			IdleConnTimeout: timeout * time.Second,
			TLSClientConfig: tlsConfig,
		}
	}
	return &HttpClient{
		client:   client,
		user:     user,
		password: password,
	}
}

func (s *Server) livenessProbe(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Header().Set("Content-Type", "application/text")
	_, err := io.WriteString(w, http.StatusText(http.StatusOK))
	if err != nil {
		slog.Error("Can't send response")
	}
}

func (s *Server) readinessProbe(w http.ResponseWriter, _ *http.Request) {
	if isHealth {
		w.WriteHeader(http.StatusOK)
		w.Header().Set("Content-Type", "application/text")
		_, err := io.WriteString(w, http.StatusText(http.StatusOK))
		if err != nil {
			slog.Error("Can't send response")
		}
	} else {
		slog.Error("Readiness probe failed")
		w.WriteHeader(http.StatusInternalServerError)
	}
}

func (s *Server) isHealth() bool {
	if strings.EqualFold(s.storage, cassandra) {
		return s.cassandraHealth()
	}
	return s.opensearchHealth()
}

func (s *Server) cassandraHealth() bool {
	errors := 0
	for errors < s.errorsCount {
		if s.cassandra != nil {
			query := s.cassandra.Query(fmt.Sprintf("SELECT * FROM %s.%s limit 1;", s.keyspace, s.testTable))
			if query != nil {
				err := query.Exec()
				if err != nil {
					slog.Error("Can't select from table. The error from server: ", "error", err.Error())
				} else {
					return true
				}
			}
		}
		errors += 1
		slog.Info(fmt.Sprintf("Remaining attempts: %d", s.errorsCount-errors))
		if errors >= s.errorsCount {
			return false
		}
		slog.Info("Sleep for 5 sec and try again")
		time.Sleep(5 * time.Second)
	}
	return false
}

func (s *Server) opensearchHealth() bool {
	req, _ := http.NewRequest(http.MethodGet, s.endpoint, http.NoBody)
	req.SetBasicAuth(s.opensearch.user, s.opensearch.password)

	errors := 0
	for errors < s.errorsCount {
		res, err := s.opensearch.client.Do(req)
		for (err != nil) && (errors < s.errorsCount) {
			errors += 1
			slog.Error(fmt.Sprintf("Catch an error: %s, remaining attempts: %d", err.Error(), s.errorsCount-errors))
			res, err = s.opensearch.client.Do(req)
		}
		if err != nil {
			slog.Error(err.Error())
			return false
		}
		if err := res.Body.Close(); err != nil {
			slog.Error(fmt.Sprintf("Error closing response body: %s", err.Error()))
		}
		retries := 0
		for retries < s.retryCount {
			if res.StatusCode == 200 {
				return true
			} else {
				slog.Info(fmt.Sprintf("Get response code: %d", res.StatusCode))
				if res.StatusCode == http.StatusTooManyRequests {
					if retries < s.retryCount {
						slog.Info("Sleep for 60 sec and try again")
						time.Sleep(60 * time.Second)
					} else {
						slog.Error("Can't get response from opensearch for a long time")
						return false
					}
				} else {
					slog.Info(fmt.Sprintf("Remaining attempts: %d", s.retryCount-retries))
				}
				retries += 1
				res, err = s.opensearch.client.Do(req)
				if err != nil {
					slog.Error(err.Error())
					return false
				}
			}
		}
	}
	return false
}

func createSessionWithRetry(cluster *gocql.ClusterConfig, maxRetries int, retryDelay time.Duration) (*gocql.Session, error) {
	for i := 1; i <= maxRetries; i++ {
		session, err := cluster.CreateSession()
		if err == nil {
			return session, nil
		}
		slog.Error("Failed to create Cassandra session", "attempt", i, "err", err)
		time.Sleep(retryDelay)
	}
	return nil, fmt.Errorf("failed to create Cassandra session after %d attempts", maxRetries)
}
