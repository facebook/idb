#!/bin/bash

# Tap calibration targets for the app
# Based on the screenshot showing 5 blue circular targets with + symbols

# Make sure idb_companion is running
echo "Tapping calibration targets..."

# Target 1: Top-left (approximately 20%, 20%)
# For a typical iPhone screen (390x844 points), this would be around (78, 169)
echo "Tapping target 1..."
grpcurl -plaintext -d '{
  "press": {
    "action": {
      "touch": {
        "point": {
          "x": 78,
          "y": 169
        }
      }
    },
    "direction": "DOWN"
  }
}' localhost:10882 idb.CompanionService/hid

grpcurl -plaintext -d '{
  "press": {
    "action": {
      "touch": {
        "point": {
          "x": 78,
          "y": 169
        }
      }
    },
    "direction": "UP"
  }
}' localhost:10882 idb.CompanionService/hid

sleep 1

# Target 2: Top-right (approximately 80%, 20%)
echo "Tapping target 2..."
grpcurl -plaintext -d '{
  "press": {
    "action": {
      "touch": {
        "point": {
          "x": 312,
          "y": 169
        }
      }
    },
    "direction": "DOWN"
  }
}' localhost:10882 idb.CompanionService/hid

grpcurl -plaintext -d '{
  "press": {
    "action": {
      "touch": {
        "point": {
          "x": 312,
          "y": 169
        }
      }
    },
    "direction": "UP"
  }
}' localhost:10882 idb.CompanionService/hid

sleep 1

# Target 3: Center (approximately 50%, 60%)
echo "Tapping target 3..."
grpcurl -plaintext -d '{
  "press": {
    "action": {
      "touch": {
        "point": {
          "x": 195,
          "y": 506
        }
      }
    },
    "direction": "DOWN"
  }
}' localhost:10882 idb.CompanionService/hid

grpcurl -plaintext -d '{
  "press": {
    "action": {
      "touch": {
        "point": {
          "x": 195,
          "y": 506
        }
      }
    },
    "direction": "UP"
  }
}' localhost:10882 idb.CompanionService/hid

sleep 1

# Target 4: Bottom-left (approximately 20%, 80%)
echo "Tapping target 4..."
grpcurl -plaintext -d '{
  "press": {
    "action": {
      "touch": {
        "point": {
          "x": 78,
          "y": 675
        }
      }
    },
    "direction": "DOWN"
  }
}' localhost:10882 idb.CompanionService/hid

grpcurl -plaintext -d '{
  "press": {
    "action": {
      "touch": {
        "point": {
          "x": 78,
          "y": 675
        }
      }
    },
    "direction": "UP"
  }
}' localhost:10882 idb.CompanionService/hid

sleep 1

# Target 5: Bottom-right (approximately 80%, 80%)
echo "Tapping target 5..."
grpcurl -plaintext -d '{
  "press": {
    "action": {
      "touch": {
        "point": {
          "x": 312,
          "y": 675
        }
      }
    },
    "direction": "DOWN"
  }
}' localhost:10882 idb.CompanionService/hid

grpcurl -plaintext -d '{
  "press": {
    "action": {
      "touch": {
        "point": {
          "x": 312,
          "y": 675
        }
      }
    },
    "direction": "UP"
  }
}' localhost:10882 idb.CompanionService/hid

echo "All calibration targets tapped!"