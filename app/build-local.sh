#!/usr/bin/env bash
# Build and install the app against your own server.
#
# Everything that identifies a particular setup lives in two git-ignored
# files and nowhere else:
#
#   .env.local-build                 which server to talk to
#   ios/Flutter/LocalSigning.xcconfig  which Apple identity to sign with
#
# so a fresh clone builds upstream Omi, and this builds yours.
set -euo pipefail
cd "$(dirname "$0")"

[ -f .env.local-build ] || { echo "missing .env.local-build (see .env.local-build.example)" >&2; exit 1; }
set -a; . ./.env.local-build; set +a

echo "building against ${OMI_LOCAL_API_BASE_URL}"
exec bash setup.sh "${1:-ios}"
