package dlclicense

import "testing"

func TestWholesaleActivationCodeDeterministic(t *testing.T) {
	id := "AABBCCDDEEFF11223344556677889900"
	a := WholesaleActivationCode(id)
	b := WholesaleActivationCode(id)
	if a != b || len(a) != 14 || a[:2] != "WS" {
		t.Fatalf("unexpected code: %q", a)
	}
}

func TestPOSActivationCodeDeterministic(t *testing.T) {
	id := "AABBCCDDEEFF11223344556677889900"
	a := POSActivationCode(id)
	b := POSActivationCode(id)
	if a != b || len(a) != 14 || a[:2] != "PS" {
		t.Fatalf("unexpected code: %q", a)
	}
}

func TestValidateWholesaleCodeAcceptsFormattedInput(t *testing.T) {
	id := "AABBCCDDEEFF11223344556677889900"
	code := WholesaleActivationCode(id)
	formatted := FormatWholesaleCode(code)
	if !ValidateWholesaleCode(id, formatted) {
		t.Fatalf("formatted code should validate: %s", formatted)
	}
}

func TestValidatePOSCodeAcceptsFormattedInput(t *testing.T) {
	id := "AABBCCDDEEFF11223344556677889900"
	code := POSActivationCode(id)
	formatted := FormatPOSCode(code)
	if !ValidatePOSCode(id, formatted) {
		t.Fatalf("formatted code should validate: %s", formatted)
	}
}

func TestNormalizeInstallationID(t *testing.T) {
	cases := map[string]string{
		"ABCD1234-EFGH5678-IJKL9012-MNOP3456": "ABCD1234EFGH5678IJKL9012MNOP3456",
		"abcd1234efgh5678":                    "ABCD1234EFGH5678",
		"MAC-AA:BB:CC:DD:EE:FF":               "AABBCCDDEEFF",
	}
	for in, want := range cases {
		if got := NormalizeInstallationID(in); got != want {
			t.Fatalf("%q: got %q want %q", in, got, want)
		}
	}
}

func TestValidateRejectsWrongInstallationID(t *testing.T) {
	code := WholesaleActivationCode("AABBCCDDEEFF11223344556677889900")
	if ValidateWholesaleCode("11223344556677889900AABBCCDDEEFF", code) {
		t.Fatal("should not validate for different installation id")
	}
}

func TestWholesaleAndPOSCodesDiffer(t *testing.T) {
	id := "AABBCCDDEEFF11223344556677889900"
	ws := WholesaleActivationCode(id)
	ps := POSActivationCode(id)
	if ws == ps {
		t.Fatal("wholesale and pos codes should differ")
	}
}
