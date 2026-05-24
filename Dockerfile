FROM python:3.13
WORKDIR /app
COPY python_loop_output.py .
EXPOSE 8080
CMD [ "python", "-u", "python_loop_output.py" ]
