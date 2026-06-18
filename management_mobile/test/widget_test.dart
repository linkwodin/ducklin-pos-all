import 'package:flutter_test/flutter_test.dart';
import 'package:management_mobile/utils/jwt_utils.dart';

void main() {
  test('JwtUtils treats malformed token as expired', () {
    expect(JwtUtils.isExpired('not-a-jwt'), isTrue);
  });
}
