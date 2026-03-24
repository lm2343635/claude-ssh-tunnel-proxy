.PHONY: start stop status socks-on socks-off log install

start:
	@bash start.sh

stop:
	@bash stop.sh

status:
	@bash proxy status

socks-on:
	@bash proxy socks-on

socks-off:
	@bash proxy socks-off

log:
	@tail -f /tmp/ssh-tunnel.log

install:
	@bash install.sh
