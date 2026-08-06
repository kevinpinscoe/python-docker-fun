# -slim, not the full image. python_loop_output.py imports nothing outside the
# standard library (os, signal, sys, threading, datetime, http.server), so the full
# Debian image contributed a compiler toolchain, dev headers and assorted libraries
# that this container never executes — and every CVE in them.
#
# Measured 2026-08-05 on the full image: 1949 findings, 444 of them high or critical,
# essentially all inherited and some dating to 2009. That is why the CVE gate in the
# release workflow is warn-only; the honest fix was always a smaller base rather than
# a louder gate.
FROM python:3.14-slim
WORKDIR /app
COPY python_loop_output.py .
EXPOSE 8080
CMD [ "python", "-u", "python_loop_output.py" ]
