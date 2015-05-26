# KVM make targets, for Libreswan
#
# Copyright (C) 2015 Andrew Cagney <cagney@gnu.org>
# 
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 2 of the License, or (at your
# option) any later version.  See <http://www.fsf.org/copyleft/gpl.txt>.
# 
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.

# XXX: GNU Make doesn't let you combine pattern targets (e.x.,
# kvm-install-%: kvm-reboot-%) with .PHONY.  Consequently, so that
# patterns can be used, any targets with dependencies are not marked
# as .PHONY.  Sigh!

# XXX: For compatibility
abs_top_srcdir ?= $(abspath ${LIBRESWANSRCDIR})

KVMSH_COMMAND ?= $(abs_top_srcdir)/testing/utils/kvmsh.py
KVM_MOUNTS_COMMAND ?= $(abs_top_srcdir)/testing/utils/kvmmounts.sh
KVM_SWANTEST_COMMAND ?= $(abs_top_srcdir)/testing/utils/swantest

KVM_HOSTS = east west road north

# NOTE: Use this from make rules only.  Determines the KVM path to
# $(abs_top_srcdir).  If broken, override using Makefile.inc.local
KVM_HOST = $(lastword $(subst -, ,$@))
KVM_BUILD_MOUNT ?= $(shell $(KVM_MOUNTS_COMMAND) $(1) swansource)
KVM_BUILD_SUBDIR ?= $(subst $(call KVM_BUILD_MOUNT,$(1)),,$(abs_top_srcdir))
KVM_TARGET_SOURCEDIR ?= $(patsubst %/,%,/source/$(patsubst /%,%,$(call KVM_BUILD_SUBDIR,$(1))))
KVM_EASTDIR ?= $(call KVM_TARGET_SOURCEDIR,east)

KVMSH_TARGETS = $(patsubst %,kvmsh-%,$(KVM_HOSTS))
.PHONY: $(KVMSH_TARGETS)
$(KVMSH_TARGETS):
	: COMMAND: '$(COMMAND)'
	: KVM_HOST: '$(KVM_HOST)'
	$(KVMSH_COMMAND) --chdir . '$(KVM_HOST)' $(if $(COMMAND),'$(COMMAND)')
.PHONY: kvmsh
kvmsh: kvmsh-command | $(KVMSH_TARGETS)
.PHONY: kvmsh-command
kvmsh-command:
	test '$(COMMAND)' != ''

KVM_SHUTDOWN_TARGETS = $(patsubst %,kvm-shutdown-%,$(KVM_HOSTS))
.PHONY: $(KVM_SHUTDOWN_TARGETS)
$(KVM_SHUTDOWN_TARGETS):
	: KVM_HOST: '$(KVM_HOST)'
	$(KVMSH_COMMAND) --shutdown '$(KVM_HOST)'
.PHONY: kvm-shutdown
kvm-shutdown: $(KVM_SHUTDOWN_TARGETS)

KVM_BUILD_TARGETS = $(patsubst %,kvm-build-%,$(KVM_HOSTS))
.PHONY: $(KVM_BUILD_TARGETS)
$(KVM_BUILD_TARGETS):
	: KVM_HOST: '$(KVM_HOST)'
	$(KVMSH_COMMAND) --chdir . '$(KVM_HOST)' ./testing/guestbin/swan-build

KVM_INSTALL_TARGETS = $(patsubst %,kvm-install-%,$(KVM_HOSTS))
.PHONY: $(KVM_INSTALL_TARGETS)
$(KVM_INSTALL_TARGETS):
	: KVM_HOST: '$(KVM_HOST)'
	$(KVMSH_COMMAND) --chdir . '$(KVM_HOST)' ./testing/guestbin/swan-install

.PHONY: kvm-update
kvm-update: kvm-build-east | $(KVM_INSTALL_TARGETS)

KVM_EXCLUDE = bad|wip|incomplete
KVM_EXCLUDE_FLAG = $(if $(KVM_EXCLUDE),--exclude '$(KVM_EXCLUDE)')
KVM_INCLUDE =
KVM_INCLUDE_FLAG = $(if $(KVM_INCLUDE),--include '$(KVM_INCLUDE)')
NEWRUN = $(if $(wildcard kvm-checksum.new),--newrun)
.PHONY: kvm-check
kvm-check: kvm-checksum
	: $@:
	:   PWD: $(PWD)
	:   KVM_HOSTS: $(KVM_HOSTS)
	:   KVM_PRINT_TARGETS: $(KVM_PRINT_TARGETS)
	:   KVM_EASTDIR: $(KVM_EASTDIR)
	:   KVM_EXCLUDE: '$(KVM_EXCLUDE)'
	:     KVM_EXCLUDE_FLAG: $(KVM_EXCLUDE_FLAG)
	:   KVM_INCLUDE: '$(KVM_INCLUDE)'
	:     KVM_INCLUDE_FLAG: $(KVM_INCLUDE_FLAG)
	:   NEWRUN: $(NEWRUN)
	cd testing/pluto && $(KVM_SWANTEST_COMMAND) $(NEWRUN) --testingdir $(KVM_EASTDIR)/testing $(KVM_INCLUDE_FLAG) $(KVM_EXCLUDE_FLAG)

# Hide a make call
SHOWVERSION = $(MAKE) showversion

# Detect either a new or updated install or test.
#
# The file kvm-checksum.new is left as a marker for $(NEWRUN).
#
# The checksums for both the installed tree (on east) and the source
# tree are recorded.  Presumably if either changes then it is a new
# run.  The /etc directory is excluded as the tests play havoc with
# its contents.
.PHONY: kvm-checksum
kvm-checksum:
	$(KVMSH_COMMAND) --chdir . east 'make list-base | grep '^/' | grep -v '^/etc' | xargs md5sum' | tee kvm-checksum.new
	$(SHOWVERSION) | tee -a kvm-checksum.new
	if test -r kvm-checksum && cmp kvm-checksum.new kvm-checksum ; then \
		echo "Checksum file unchanged" ; \
		rm kvm-checksum.new ; \
	else \
		echo "Checksum file CHANGED" ; \
		cp kvm-checksum.new kvm-checksum ; \
	fi