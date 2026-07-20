import 'package:flutter_test/flutter_test.dart';
import 'package:eforward_app/config/tenant.dart';

void main() {
  const tmpl = 'https://eforward-api.{domain}/api';

  test('derives backend URL from email domain (existing tenants)', () {
    expect(TenantResolver.domainOf('ramon.napa@ardentnetworks.com.ph'),
        'ardentnetworks.com.ph');
    expect(
        TenantResolver.apiBaseUrlFor('ardentnetworks.com.ph', tmpl),
        'https://eforward-api.ardentnetworks.com.ph/api');
    expect(
        TenantResolver.apiBaseUrlFor('versatech.com.ph', tmpl),
        'https://eforward-api.versatech.com.ph/api');
  });

  test('open: any new domain routes with no code change', () {
    final d = TenantResolver.domainOf('new.user@acme.com.ph');
    expect(d, 'acme.com.ph');
    expect(TenantResolver.apiBaseUrlFor(d!, tmpl),
        'https://eforward-api.acme.com.ph/api');
  });

  test('rejects malformed / unroutable emails', () {
    expect(TenantResolver.domainOf('bad-no-domain'), isNull);
    expect(TenantResolver.domainOf('user@localhost'), isNull);
    expect(TenantResolver.domainOf('a@.dot'), isNull);
    expect(TenantResolver.domainOf('@nolocal.com'), isNull);
  });
}
