//go:build ignore

// gen-cert.go generates a self-signed TLS certificate that is fully compliant
// with Go's crypto/x509 standards checks (Go 1.15+).
//
// Usage:
//
//	go run scripts/gen-cert.go -out ./certs -ip 127.0.0.1,10.200.10.1 -dns localhost
package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"flag"
	"fmt"
	"log"
	"math/big"
	"net"
	"os"
	"strings"
	"time"
)

func main() {
	out := flag.String("out", "./certs", "output directory")
	rawIPs := flag.String("ip", "127.0.0.1", "comma-separated IP SANs")
	rawDNS := flag.String("dns", "localhost", "comma-separated DNS SANs")
	days := flag.Int("days", 3650, "certificate validity in days")
	flag.Parse()

	if err := os.MkdirAll(*out, 0o755); err != nil {
		log.Fatal(err)
	}

	// Parse IPs
	var ipList []net.IP
	for _, s := range strings.Split(*rawIPs, ",") {
		s = strings.TrimSpace(s)
		if s == "" {
			continue
		}
		ip := net.ParseIP(s)
		if ip == nil {
			log.Fatalf("invalid IP: %s", s)
		}
		ipList = append(ipList, ip)
	}

	// Parse DNS names
	var dnsList []string
	for _, s := range strings.Split(*rawDNS, ",") {
		s = strings.TrimSpace(s)
		if s != "" {
			dnsList = append(dnsList, s)
		}
	}

	// Generate ECDSA P-256 private key
	priv, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		log.Fatalf("generate key: %v", err)
	}

	// Random positive serial number (required by RFC 5280)
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		log.Fatalf("serial: %v", err)
	}

	now := time.Now()
	tmpl := &x509.Certificate{
		SerialNumber: serial,
		Subject: pkix.Name{
			Organization: []string{"remotectl"},
			CommonName:   "remotectl",
		},
		NotBefore: now.Add(-time.Minute), // 1 min skew tolerance
		NotAfter:  now.Add(time.Duration(*days) * 24 * time.Hour),

		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
		IsCA:                  false,

		IPAddresses: ipList,
		DNSNames:    dnsList,
	}

	// Self-sign
	certDER, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &priv.PublicKey, priv)
	if err != nil {
		log.Fatalf("create cert: %v", err)
	}

	certPath := *out + "/server.crt"
	keyPath := *out + "/server.key"

	cf, err := os.Create(certPath)
	if err != nil {
		log.Fatal(err)
	}
	pem.Encode(cf, &pem.Block{Type: "CERTIFICATE", Bytes: certDER})
	cf.Close()

	privDER, err := x509.MarshalECPrivateKey(priv)
	if err != nil {
		log.Fatalf("marshal key: %v", err)
	}
	kf, err := os.Create(keyPath)
	if err != nil {
		log.Fatal(err)
	}
	pem.Encode(kf, &pem.Block{Type: "EC PRIVATE KEY", Bytes: privDER})
	kf.Close()

	// Verify it passes Go's own compliance check
	certPEM, _ := os.ReadFile(certPath)
	block, _ := pem.Decode(certPEM)
	if _, err := x509.ParseCertificate(block.Bytes); err != nil {
		log.Fatalf("generated cert failed Go compliance check: %v", err)
	}

	fmt.Printf("Certificate : %s\n", certPath)
	fmt.Printf("Key         : %s\n", keyPath)
	fmt.Printf("Valid for   : %d days\n", *days)
	fmt.Printf("IPs         : %v\n", ipList)
	fmt.Printf("DNS         : %v\n", dnsList)
	fmt.Println()
	fmt.Println("Start server:")
	fmt.Printf("  ./bin/remotectl-server --tls-cert %s --tls-key %s\n", certPath, keyPath)
}
