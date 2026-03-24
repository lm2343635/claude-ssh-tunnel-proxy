#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PATH="/usr/local/bin/proxy"

chmod +x "${SCRIPT_DIR}/proxy"
chmod +x "${SCRIPT_DIR}/start.sh"
chmod +x "${SCRIPT_DIR}/stop.sh"

if [ -L "${INSTALL_PATH}" ] || [ -e "${INSTALL_PATH}" ]; then
    echo "Removing existing ${INSTALL_PATH}..."
    sudo rm "${INSTALL_PATH}"
fi

sudo ln -s "${SCRIPT_DIR}/proxy" "${INSTALL_PATH}"
echo "Installed: proxy -> ${SCRIPT_DIR}/proxy"
echo ""
echo "Usage:"
echo "  proxy start   - Start the tunnel"
echo "  proxy stop    - Stop the tunnel"
echo "  proxy status  - Check tunnel status"
echo "  proxy log     - View logs"
