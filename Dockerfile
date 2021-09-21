ARG VPP_VERSION=v21.06.0-11-013a20f3d
FROM ghcr.io/edwarnicke/govpp/vpp:${VPP_VERSION} as go
COPY --from=golang:1.16.3-buster /usr/local/go/ /go
ENV PATH ${PATH}:/go/bin
ENV GO111MODULE=on
ENV CGO_ENABLED=0
ENV GOBIN=/bin
RUN rm -r /etc/vpp
RUN go get github.com/go-delve/delve/cmd/dlv@v1.6.0
RUN go get github.com/grpc-ecosystem/grpc-health-probe@v0.4.1
RUN go get github.com/edwarnicke/dl
RUN dl \
    https://github.com/spiffe/spire/releases/download/v0.9.3/spire-0.9.3-linux-x86_64-glibc.tar.gz | \
    tar -xzvf - -C /bin --strip=3 ./spire-0.9.3/bin/spire-server ./spire-0.9.3/bin/spire-agent

FROM go as build
WORKDIR /build
COPY go.mod go.sum ./
COPY ./local ./local
COPY ./internal/imports ./internal/imports
RUN go build ./internal/imports
COPY . .
RUN go build -o /bin/forwarder .

FROM build as test
ENV NSM_DEVICE_PLUGIN_PATH=/build/run/device-plugins
RUN mkdir -p ${NSM_DEVICE_PLUGIN_PATH}
ENV NSM_POD_RESOURCES_PATH=/build/run/pod-resources
RUN mkdir -p ${NSM_POD_RESOURCES_PATH}
ENV NSM_SRIOV_CONFIG_FILE=/dev/null
CMD go test -test.v ./...

FROM test as debug
WORKDIR /build/internal/tests/
CMD dlv -l :40000 --headless=true --api-version=2 test -test.v .

FROM ghcr.io/edwarnicke/govpp/vpp:${VPP_VERSION} as runtime
COPY --from=build /bin/forwarder /bin/forwarder
COPY --from=build /bin/grpc-health-probe /bin/grpc-health-probe
ENTRYPOINT [ "/bin/forwarder" ]
