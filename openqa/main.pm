# SPDX-License-Identifier: GPL-2.0-or-later
# Vibes openQA test distribution entry point (casedir).
# Runs the serial-console test modules against the image booted under QEMU
# by the os-autoinst qemu backend (see .github/workflows/openqa.yml).
use Mojo::Base -strict;
use testapi;
use autotest;

autotest::loadtest 'tests/boot.pm';

1;
