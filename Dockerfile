# -alpine, not -slim, and not the full image.
#
# python_loop_output.py imports nothing outside the standard library — os, signal,
# sys, threading, datetime and http.server — so everything else in the base is
# payload this container never executes, and every CVE in it is inherited.
#
# Measured on the same day with the same Grype database:
#
#   python:3.14          1949 findings   444 high or critical
#   python:3.14-slim      177 findings    30 high or critical
#   python:3.14-alpine     12 findings     3 high or critical
#
# -slim is still Debian and still ships 87 packages, including perl-base (12 of the
# 30 findings), ncurses, sqlite3 and gzip — base-system furniture that dpkg drags in,
# none of which a stdlib-only Python script touches. Alpine's musl base carries none
# of it.
#
# The 3 that remain are in CPython itself and are fixed only in 3.15.0/3.15.0b4, a
# future major version currently in beta — so they cannot be cleared by upgrading
# within the 3.14 line. See .vex/ and the README for how they are dispositioned.
FROM python:3.14-alpine
WORKDIR /app
COPY python_loop_output.py .
EXPOSE 8080
CMD [ "python", "-u", "python_loop_output.py" ]
