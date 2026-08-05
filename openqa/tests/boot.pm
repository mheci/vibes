# SPDX-License-Identifier: GPL-2.0-or-later
# Boot test: wait for the login prompt on the serial console.
#
# The os-autoinst qemu backend always attaches a serial device to the guest
# (chardev ringbuf logging to the serial0 file) and wait_serial reads that
# log, so this module needs no needles and works headless under TCG.
#
# The disk image is built with --karg console=ttyS0,115200 (see
# .github/workflows/openqa.yml), which makes systemd start a getty on
# ttyS0 and print the kernel/boot messages there.
use Mojo::Base 'basetest';
use testapi;

sub run {
    # Long timeout: the image boots in software emulation (no KVM on
    # GitHub-hosted runners), which can take several minutes.
    wait_serial(qr/login:/i, timeout => 1500)
      or die 'Boot test failed: login prompt never appeared on the serial console';

    record_info 'boot', 'Vibes image booted to the login prompt';
}

1;
