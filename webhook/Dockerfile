FROM golang:1.26.5 AS build
WORKDIR /src
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/webhook .

FROM gcr.io/distroless/static-debian13:nonroot
COPY --from=build /out/webhook /webhook
USER nonroot:nonroot
ENTRYPOINT ["/webhook"]
