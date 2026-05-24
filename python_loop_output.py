# Kevin test loop
# Used for debugging and testing Kubernetes pods

import time
from datetime import datetime, timezone

version = "3.0"

i = 0
while True:
    current_time = datetime.now(timezone.utc).strftime("%H:%M:%S")
    print(f"Version: {version}: [{i}] Current Time = {current_time}")
    i += 1
    time.sleep(60)
