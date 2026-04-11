#!/bin/bash
echo "=== Superadmin şifre fix ==="

HASH=$(docker run --rm python:3.11-alpine sh -c "pip install bcrypt -q 2>/dev/null && python -c \"import bcrypt; h = bcrypt.hashpw(b'pls_change_me', bcrypt.gensalt(10)).decode(); print(h.replace('\$2b\$', '\$2a\$'))\"")

echo "Hash üretildi, DB güncelleniyor..."
docker exec atlas_db psql -U rootUser -d atlas -c "UPDATE own_user SET password = '$HASH' WHERE email = 'superadmin@test.com';"

RESPONSE=$(curl -s -X POST http://localhost:8080/auth/signin \
  -H "Content-Type: application/json" \
  -d '{"email":"superadmin@test.com","password":"pls_change_me","type":"client"}')

if echo "$RESPONSE" | grep -q "accessToken"; then
  echo "✅ Superadmin girişi başarılı!"
else
  echo "❌ Giriş başarısız: $RESPONSE"
fi
