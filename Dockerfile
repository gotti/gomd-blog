FROM golang:1.27-alpine

WORKDIR /app
COPY . /app

RUN go build -o main ./app/app.go

CMD ["/app/main"]
