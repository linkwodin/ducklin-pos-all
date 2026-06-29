package main

import (
	"fmt"
	"os"
	"strings"

	"pos-system/backend/pkg/dlclicense"
)

func main() {
	if len(os.Args) < 3 {
		printUsage()
		os.Exit(1)
	}
	feature := strings.ToLower(strings.TrimSpace(os.Args[1]))
	installationID := strings.TrimSpace(os.Args[2])
	if installationID == "" {
		fmt.Fprintln(os.Stderr, "installation id is required")
		os.Exit(1)
	}

	id := dlclicense.NormalizeInstallationID(installationID)
	if id == "" {
		fmt.Fprintln(os.Stderr, "could not parse installation id")
		os.Exit(1)
	}

	switch feature {
	case dlclicense.FeatureWholesale:
		code := dlclicense.WholesaleActivationCode(id)
		fmt.Println("Installation ID:", id)
		fmt.Println("Wholesale DLC code:", dlclicense.FormatWholesaleCode(code))
	case dlclicense.FeaturePOS:
		code := dlclicense.POSActivationCode(id)
		fmt.Println("Installation ID:", id)
		fmt.Println("POS DLC code:", dlclicense.FormatPOSCode(code))
	default:
		fmt.Fprintf(os.Stderr, "unknown feature %q\n", feature)
		printUsage()
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Fprintf(os.Stderr, `Usage:
  dlc-gen wholesale <installation-id>
  dlc-gen pos <installation-id>

<installation-id> is shown on Management → System information.

Build from repo root:
  go run ./backend/cmd/dlc-gen wholesale "XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX"
  go run ./backend/cmd/dlc-gen pos "XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX"
`)
}
