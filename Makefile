all: build

.PHONY: all build
build:
	docker build -t kafka .


