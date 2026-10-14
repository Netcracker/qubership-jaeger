package secret

import (
	"context"
	"fmt"

	v1 "k8s.io/api/core/v1"
	metaV1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"

	"tracing-readiness-probe/internal/probes"
)

// ReadCredentials reads the storage username and password from a basic-auth Secret.
func ReadCredentials(ctx context.Context, client kubernetes.Interface, namespace, name string) (probes.Credentials, error) {
	secret, err := client.CoreV1().Secrets(namespace).Get(ctx, name, metaV1.GetOptions{})
	if err != nil {
		return probes.Credentials{}, fmt.Errorf("failed to read the secret '%s/%s': %w", namespace, name, err)
	}

	username, err := readField(secret, v1.BasicAuthUsernameKey)
	if err != nil {
		return probes.Credentials{}, err
	}
	password, err := readField(secret, v1.BasicAuthPasswordKey)
	if err != nil {
		return probes.Credentials{}, err
	}
	return probes.Credentials{Username: username, Password: password}, nil
}

func readField(secret *v1.Secret, key string) (string, error) {
	value := string(secret.Data[key])
	if value == "" {
		return "", fmt.Errorf("the field '%s' is missing or empty in the secret '%s/%s'", key, secret.Namespace, secret.Name)
	}
	return value, nil
}
