# Log functions for scripts.
#
# Suitable for Xcode Run Script Build Phase and command line scripts.
#
# Usage:
#
# source bin/log.sh

function info {
  if [ "${TERM}" = "dumb" ]; then
    echo "INFO: $1"
  else
    echo "$(tput setaf 2)INFO: $1$(tput sgr0)"
  fi
}

function warn {
  if [ "${TERM}" = "dumb" ]; then
    echo "WARN: $1"
  else
    echo "$(tput setaf 3)WARN: $1$(tput sgr0)"
  fi
}

function error {
  if [ "${TERM}" = "dumb" ]; then
    echo "ERROR: $1"
  else
    echo "$(tput setaf 1)ERROR: $1$(tput sgr0)"
  fi
}

function banner {
  if [ "${TERM}" = "dumb" ]; then
    echo ""
    echo "######## $1 ########"
    echo ""
  else
    echo ""
    echo "$(tput setaf 5)######## $1 ########$(tput sgr0)"
    echo ""
  fi
}

