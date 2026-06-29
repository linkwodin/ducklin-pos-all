# dlc-gen

Generates installation-bound DLC activation codes for optional POS features.

## Installation ID

On first startup the backend generates a random **Installation ID** and stores it in company settings. Open **Management → System information** and copy **Installation ID**.

## Wholesale module

```bash
go run ./backend/cmd/dlc-gen wholesale "<installation-id>"
```

Enter the printed code (`WS-XXXX-XXXX-XXXX`) when enabling wholesale orders in Company settings.

## POS module

```bash
go run ./backend/cmd/dlc-gen pos "<installation-id>"
```

Enter the printed code (`PS-XXXX-XXXX-XXXX`) when enabling the POS module in Company settings.

Codes are deterministic for that installation ID and only validate on the matching system.
