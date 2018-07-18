# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright © 2016-2018 ANSSI. All Rights Reserved.
CFLAGS= -fPIC -Wall -pedantic -Wextra
CC=gcc
LDFLAGS=-static# -pie

BIN = src/wrapper-lxc-mirror-start \
	 src/wrapper-lxc-mirror-stop \
	 src/wrapper-lxc-test-start \
	 src/wrapper-lxc-test-stop \
	 src/wrapper-lxc-update \
	 src/wrapper-lxc-update-stop

.PHONY: all install clean mrproper

all: install
	fakeroot -- dpkg-deb --build debian .

install:  ${BIN}
	mkdir -p  debian/usr/share/clip-buildbot/bin || true
	mv ${BIN} debian/usr/share/clip-buildbot/bin
	mkdir debian/var/lib/lxc/sdk-{mirror,test}/rootfs || true

clean:
	rm ${BIN} || true
	rm -r debian/usr/share/clip-buildbot || true
	rmdir debian/var/lib/lxc/sdk-{mirror,test}/rootfs || true

mrproper: clean
	rm clip-buildbot_*_*.deb || true
