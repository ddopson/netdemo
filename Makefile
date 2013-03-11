

.PHONY: default
default:
	dd if=/dev/random of=input_file bs=1M count=64
	npm install
