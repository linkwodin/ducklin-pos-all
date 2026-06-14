package mail

import (
	"crypto/rand"
	"crypto/tls"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"mime"
	"net"
	"net/mail"
	"net/smtp"
	"strings"
	"time"
)

// Attachment is a file attached to an email.
type Attachment struct {
	Filename    string
	ContentType string
	Data        []byte
}

// defaultNoReplyFrom returns no-reply@domain when username is user@domain, else username.
func defaultNoReplyFrom(username string) string {
	u := strings.TrimSpace(username)
	if i := strings.LastIndex(u, "@"); i > 0 && i < len(u)-1 {
		d := strings.TrimSpace(u[i+1:])
		if d != "" {
			return "no-reply@" + d
		}
	}
	return u
}

func dialSMTP(host string, port int) (net.Conn, error) {
	if port <= 0 {
		port = 587
	}
	addr := net.JoinHostPort(host, fmt.Sprintf("%d", port))
	dialer := net.Dialer{Timeout: 25 * time.Second}
	// Port 465 uses implicit TLS (SMTPS); 587 uses plain TCP then STARTTLS.
	if port == 465 {
		tcfg := &tls.Config{ServerName: host, MinVersion: tls.VersionTLS12}
		conn, err := tls.DialWithDialer(&dialer, "tcp", addr, tcfg)
		if err != nil {
			return nil, fmt.Errorf("smtp tls dial %s: %w", addr, err)
		}
		return conn, nil
	}
	conn, err := dialer.Dial("tcp", addr)
	if err != nil {
		return nil, fmt.Errorf("smtp tcp dial %s: %w", addr, err)
	}
	return conn, nil
}

func newAuthenticatedClient(host string, port int, username, password string) (*smtp.Client, error) {
	if host == "" || username == "" || password == "" {
		return nil, fmt.Errorf("smtp not configured")
	}
	if port <= 0 {
		port = 587
	}
	conn, err := dialSMTP(host, port)
	if err != nil {
		return nil, err
	}
	client, err := smtp.NewClient(conn, host)
	if err != nil {
		_ = conn.Close()
		return nil, fmt.Errorf("smtp client: %w", err)
	}
	if port != 465 {
		if ok, _ := client.Extension("STARTTLS"); ok {
			tcfg := &tls.Config{ServerName: host, MinVersion: tls.VersionTLS12}
			if err = client.StartTLS(tcfg); err != nil {
				_ = client.Close()
				return nil, fmt.Errorf("smtp starttls: %w", err)
			}
		}
	}
	auth := smtp.PlainAuth("", username, password, host)
	if err = client.Auth(auth); err != nil {
		_ = client.Close()
		return nil, fmt.Errorf("smtp auth: %w", err)
	}
	return client, nil
}

// SendPlain sends a UTF-8 plain-text email via SMTP (587+STARTTLS or 465+TLS).
func SendPlain(host string, port int, username, password, fromAddr string, to []string, subject, body string) error {
	if len(to) == 0 {
		return fmt.Errorf("no recipients")
	}
	if fromAddr == "" {
		fromAddr = defaultNoReplyFrom(username)
	}

	client, err := newAuthenticatedClient(host, port, username, password)
	if err != nil {
		return err
	}
	defer func() { _ = client.Close() }()

	// Envelope MAIL FROM / RCPT TO: pass bare user@host only. Go's smtp.Mail/Rcpt emit
	// MAIL FROM:<%s> / RCPT TO:<%s>; wrapping here in extra angles causes
	// MAIL FROM:<<addr>> and Gmail returns 555 5.5.2 syntax errors.
	fromParsed, err := mail.ParseAddress(strings.TrimSpace(fromAddr))
	if err != nil {
		return fmt.Errorf("invalid from address: %w", err)
	}
	if fromParsed.Address == "" {
		return fmt.Errorf("empty from address")
	}
	if err = client.Mail(fromParsed.Address); err != nil {
		return fmt.Errorf("smtp mail from %q: %w", fromParsed.Address, err)
	}

	var toHdrParts []string
	for _, toAddr := range to {
		toParsed, err := mail.ParseAddress(strings.TrimSpace(toAddr))
		if err != nil {
			return fmt.Errorf("invalid to address %q: %w", toAddr, err)
		}
		if toParsed.Address == "" {
			return fmt.Errorf("empty to address")
		}
		if err = client.Rcpt(toParsed.Address); err != nil {
			return fmt.Errorf("smtp rcpt %q: %w", toParsed.Address, err)
		}
		toHdrParts = append(toHdrParts, toParsed.String())
	}
	toHdr := strings.Join(toHdrParts, ", ")

	w, err := client.Data()
	if err != nil {
		return fmt.Errorf("smtp data: %w", err)
	}
	headers := fmt.Sprintf(
		"From: %s\r\nTo: %s\r\nSubject: %s\r\nDate: %s\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n",
		fromParsed.String(),
		toHdr,
		subject,
		time.Now().UTC().Format(time.RFC1123Z),
	)
	if _, err = w.Write(append([]byte(headers), []byte(body)...)); err != nil {
		return fmt.Errorf("smtp write body: %w", err)
	}
	if err = w.Close(); err != nil {
		return fmt.Errorf("smtp close data: %w", err)
	}
	_ = client.Quit()
	return nil
}

func parseAddrList(addrs []string, field string) ([]*mail.Address, error) {
	var out []*mail.Address
	for _, raw := range addrs {
		raw = strings.TrimSpace(raw)
		if raw == "" {
			continue
		}
		parsed, err := mail.ParseAddress(raw)
		if err != nil {
			return nil, fmt.Errorf("invalid %s address %q: %w", field, raw, err)
		}
		if parsed.Address == "" {
			return nil, fmt.Errorf("empty %s address", field)
		}
		out = append(out, parsed)
	}
	return out, nil
}

func smtpConnect(host string, port int, username, password string) (*smtp.Client, error) {
	return newAuthenticatedClient(host, port, username, password)
}

func mailFromAddr(fromAddr, username string) (*mail.Address, error) {
	if fromAddr == "" {
		fromAddr = defaultNoReplyFrom(username)
	}
	fromParsed, err := mail.ParseAddress(strings.TrimSpace(fromAddr))
	if err != nil {
		return nil, fmt.Errorf("invalid from address: %w", err)
	}
	if fromParsed.Address == "" {
		return nil, fmt.Errorf("empty from address")
	}
	return fromParsed, nil
}

func rcptAll(client *smtp.Client, addrs []*mail.Address) error {
	seen := make(map[string]struct{})
	for _, a := range addrs {
		if _, ok := seen[a.Address]; ok {
			continue
		}
		seen[a.Address] = struct{}{}
		if err := client.Rcpt(a.Address); err != nil {
			return fmt.Errorf("smtp rcpt %q: %w", a.Address, err)
		}
	}
	return nil
}

func addrHeader(addrs []*mail.Address) string {
	parts := make([]string, len(addrs))
	for i, a := range addrs {
		parts[i] = a.String()
	}
	return strings.Join(parts, ", ")
}

func mimeBoundary() string {
	b := make([]byte, 12)
	_, _ = rand.Read(b)
	return "pos_" + hex.EncodeToString(b)
}

// SendWithAttachments sends a UTF-8 plain-text email with file attachments (To + optional Cc/Bcc).
func SendWithAttachments(host string, port int, username, password, fromAddr string, to, cc, bcc []string, subject, body string, attachments []Attachment) error {
	toParsed, err := parseAddrList(to, "to")
	if err != nil {
		return err
	}
	if len(toParsed) == 0 {
		return fmt.Errorf("no recipients")
	}
	ccParsed, err := parseAddrList(cc, "cc")
	if err != nil {
		return err
	}
	bccParsed, err := parseAddrList(bcc, "bcc")
	if err != nil {
		return err
	}

	fromParsed, err := mailFromAddr(fromAddr, username)
	if err != nil {
		return err
	}

	client, err := smtpConnect(host, port, username, password)
	if err != nil {
		return err
	}
	defer func() { _ = client.Close() }()

	if err = client.Mail(fromParsed.Address); err != nil {
		return fmt.Errorf("smtp mail from %q: %w", fromParsed.Address, err)
	}
	allRcpt := append(append(append([]*mail.Address{}, toParsed...), ccParsed...), bccParsed...)
	if err = rcptAll(client, allRcpt); err != nil {
		return err
	}

	w, err := client.Data()
	if err != nil {
		return fmt.Errorf("smtp data: %w", err)
	}

	boundary := mimeBoundary()
	var msg strings.Builder
	msg.WriteString(fmt.Sprintf("From: %s\r\n", fromParsed.String()))
	msg.WriteString(fmt.Sprintf("To: %s\r\n", addrHeader(toParsed)))
	if len(ccParsed) > 0 {
		msg.WriteString(fmt.Sprintf("Cc: %s\r\n", addrHeader(ccParsed)))
	}
	msg.WriteString(fmt.Sprintf("Subject: %s\r\n", mime.QEncoding.Encode("utf-8", subject)))
	msg.WriteString(fmt.Sprintf("Date: %s\r\n", time.Now().UTC().Format(time.RFC1123Z)))
	msg.WriteString("MIME-Version: 1.0\r\n")
	msg.WriteString(fmt.Sprintf("Content-Type: multipart/mixed; boundary=%q\r\n\r\n", boundary))

	msg.WriteString("--" + boundary + "\r\n")
	msg.WriteString("Content-Type: text/plain; charset=UTF-8\r\n\r\n")
	msg.WriteString(body)
	msg.WriteString("\r\n")

	for _, att := range attachments {
		fn := strings.TrimSpace(att.Filename)
		if fn == "" {
			fn = "attachment.pdf"
		}
		ct := strings.TrimSpace(att.ContentType)
		if ct == "" {
			ct = "application/octet-stream"
		}
		msg.WriteString("--" + boundary + "\r\n")
		msg.WriteString(fmt.Sprintf("Content-Type: %s; name=%q\r\n", ct, fn))
		msg.WriteString("Content-Transfer-Encoding: base64\r\n")
		msg.WriteString(fmt.Sprintf("Content-Disposition: attachment; filename=%q\r\n\r\n", fn))
		enc := base64.StdEncoding.EncodeToString(att.Data)
		for i := 0; i < len(enc); i += 76 {
			end := i + 76
			if end > len(enc) {
				end = len(enc)
			}
			msg.WriteString(enc[i:end] + "\r\n")
		}
	}
	msg.WriteString("--" + boundary + "--\r\n")

	if _, err = w.Write([]byte(msg.String())); err != nil {
		return fmt.Errorf("smtp write body: %w", err)
	}
	if err = w.Close(); err != nil {
		return fmt.Errorf("smtp close data: %w", err)
	}
	_ = client.Quit()
	return nil
}
