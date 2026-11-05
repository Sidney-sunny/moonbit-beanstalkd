package main

import (
	"bytes"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"strconv"
	"time"

	beanstalk "github.com/beanstalkd/go-beanstalk"
)

type result struct {
	Runtime    string `json:"runtime"`
	Mode       string `json:"mode"`
	Tube       string `json:"tube"`
	ID         string `json:"id"`
	BodyHex    string `json:"body_hex"`
	Deleted    bool   `json:"deleted"`
	QueueEmpty bool   `json:"queue_empty"`
}

func required(name string) (string, error) {
	value := os.Getenv(name)
	if value == "" {
		return "", fmt.Errorf("missing %s", name)
	}
	return value, nil
}

func execute() error {
	mode, err := required("BEANSTALKD_INTEROP_MODE")
	if err != nil {
		return err
	}
	tube, err := required("BEANSTALKD_INTEROP_TUBE")
	if err != nil {
		return err
	}
	fixtureHex, err := required("BEANSTALKD_INTEROP_HEX")
	if err != nil {
		return err
	}
	body, err := hex.DecodeString(fixtureHex)
	if err != nil {
		return err
	}
	host := os.Getenv("BEANSTALKD_HOST")
	if host == "" {
		host = "127.0.0.1"
	}
	port := os.Getenv("BEANSTALKD_PORT")
	if port == "" {
		port = "11300"
	}
	raw, err := net.DialTimeout("tcp", net.JoinHostPort(host, port), 5*time.Second)
	if err != nil {
		return err
	}
	defer raw.Close()
	// Bound the complete exchange, including every reference-client read/write.
	if err := raw.SetDeadline(time.Now().Add(8 * time.Second)); err != nil {
		return err
	}
	client := beanstalk.NewConn(raw)
	out := result{Runtime: "go", Mode: mode, Tube: tube}
	switch mode {
	case "put":
		id, err := beanstalk.NewTube(client, tube).Put(body, 0, 0, 30*time.Second)
		if err != nil {
			return err
		}
		out.ID = strconv.FormatUint(id, 10)
		out.BodyHex = hex.EncodeToString(body)
	case "consume":
		set := beanstalk.NewTubeSet(client, tube)
		id, actual, err := set.Reserve(time.Second)
		if err != nil {
			return err
		}
		if !bytes.Equal(actual, body) {
			return fmt.Errorf("payload mismatch: %x", actual)
		}
		if err := client.Touch(id); err != nil {
			return err
		}
		if err := client.Delete(id); err != nil {
			return err
		}
		_, _, err = set.Reserve(0)
		var connError beanstalk.ConnError
		if !errors.As(err, &connError) || connError.Err != beanstalk.ErrTimeout {
			return fmt.Errorf("expected empty queue timeout, got %v", err)
		}
		out.ID = strconv.FormatUint(id, 10)
		out.BodyHex = hex.EncodeToString(actual)
		out.Deleted = true
		out.QueueEmpty = true
	default:
		return fmt.Errorf("unknown interop mode %q", mode)
	}
	return json.NewEncoder(os.Stdout).Encode(out)
}

func main() {
	if err := execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
