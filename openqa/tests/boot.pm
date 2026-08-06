use Mojo::Base 'basetest';
use testapi;

sub run {
    wait_serial(qr/login:/i, timeout => 2400)
      or die 'Boot test failed: login prompt never appeared on the serial console';

    record_info 'boot', 'Vibes image booted to the login prompt';
}

1;
