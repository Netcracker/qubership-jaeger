package secret

import (
	"context"
	"strings"
	"testing"

	v1 "k8s.io/api/core/v1"
	metaV1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes/fake"
)

func newSecret(data map[string][]byte) *v1.Secret {
	return &v1.Secret{
		ObjectMeta: metaV1.ObjectMeta{Namespace: "tracing", Name: "jaeger-cassandra"},
		Data:       data,
	}
}

func TestReadCredentials(t *testing.T) {
	client := fake.NewClientset(newSecret(map[string][]byte{
		v1.BasicAuthUsernameKey: []byte("user"),
		v1.BasicAuthPasswordKey: []byte("pass"),
	}))

	creds, err := ReadCredentials(context.Background(), client, "tracing", "jaeger-cassandra")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if creds.Username != "user" || creds.Password != "pass" {
		t.Errorf("unexpected credentials: %+v", creds)
	}
}

func TestReadCredentialsFails(t *testing.T) {
	tests := []struct {
		name    string
		secret  *v1.Secret
		wantErr string
	}{
		{
			name:    "secret does not exist",
			secret:  &v1.Secret{ObjectMeta: metaV1.ObjectMeta{Namespace: "tracing", Name: "other"}},
			wantErr: "tracing/jaeger-cassandra",
		},
		{
			name:    "username is missing",
			secret:  newSecret(map[string][]byte{v1.BasicAuthPasswordKey: []byte("pass")}),
			wantErr: v1.BasicAuthUsernameKey,
		},
		{
			name:    "password is empty",
			secret:  newSecret(map[string][]byte{v1.BasicAuthUsernameKey: []byte("user"), v1.BasicAuthPasswordKey: {}}),
			wantErr: v1.BasicAuthPasswordKey,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			client := fake.NewClientset(tt.secret)

			_, err := ReadCredentials(context.Background(), client, "tracing", "jaeger-cassandra")
			if err == nil {
				t.Fatal("expected an error, got nil")
			}
			if !strings.Contains(err.Error(), tt.wantErr) {
				t.Errorf("expected the error to mention %q, got %q", tt.wantErr, err)
			}
		})
	}
}
