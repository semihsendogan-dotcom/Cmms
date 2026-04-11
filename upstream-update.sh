#!/bin/bash
set -e

echo "=== Atlas CMMS Upstream Update Script ==="
cd ~/atlas-source

echo ""
echo "📥 Upstream'den güncelleme çekiliyor..."
git fetch upstream

NEW_COMMITS=$(git log --oneline upstream/main ^main | wc -l | tr -d ' ')
if [ "$NEW_COMMITS" -eq 0 ]; then
  echo "✅ Upstream'de yeni commit yok."
  exit 0
fi

echo "🆕 $NEW_COMMITS yeni upstream commit bulundu."

BRANCH="upstream-merge-$(date +%Y%m%d-%H%M)"
echo ""
echo "🔀 Branch oluşturuluyor: $BRANCH"
git checkout -b $BRANCH

echo ""
echo "⚙️  Rebase yapılıyor..."
git rebase upstream/main || true

CONFLICTS=$(git diff --name-only --diff-filter=U 2>/dev/null)
if [ -n "$CONFLICTS" ]; then
  echo ""
  echo "⚠️  Conflict tespit edildi, otomatik çözüm uygulanıyor..."

  if echo "$CONFLICTS" | grep -q "UserMapper.java"; then
    git checkout --ours api/src/main/java/com/grash/mapper/UserMapper.java
    git add api/src/main/java/com/grash/mapper/UserMapper.java
    echo "  ✅ UserMapper.java → current"
  fi

  if echo "$CONFLICTS" | grep -q "VendorRepository.java"; then
    git checkout --theirs api/src/main/java/com/grash/repository/VendorRepository.java
    git add api/src/main/java/com/grash/repository/VendorRepository.java
    echo "  ✅ VendorRepository.java → upstream"
  fi

  if echo "$CONFLICTS" | grep -q "VendorService.java"; then
    git checkout --theirs api/src/main/java/com/grash/service/VendorService.java
    git add api/src/main/java/com/grash/service/VendorService.java
    echo "  ✅ VendorService.java → upstream"
  fi

  if echo "$CONFLICTS" | grep -q "tr.ts"; then
    git checkout --ours frontend/src/i18n/translations/tr.ts
    git add frontend/src/i18n/translations/tr.ts
    echo "  ✅ tr.ts → current"
  fi

  if echo "$CONFLICTS" | grep -q "rootReducer.ts"; then
    git checkout --theirs frontend/src/store/rootReducer.ts
    git add frontend/src/store/rootReducer.ts
    echo "  ✅ rootReducer.ts → upstream"
  fi

  if echo "$CONFLICTS" | grep -q "UserService.java"; then
    python3 -c "
import os, re
path = os.environ['HOME'] + '/atlas-source/api/src/main/java/com/grash/service/UserService.java'
content = open(path).read()
content = re.sub(r'<<<<<<< HEAD\n', '', content)
content = re.sub(r'=======\n.*?>>>>>>> .*?\n', '', content, flags=re.DOTALL)
open(path, 'w').write(content)
"
    git add api/src/main/java/com/grash/service/UserService.java
    echo "  ✅ UserService.java → birleştirildi"
  fi

  if echo "$CONFLICTS" | grep -q "app.tsx"; then
    python3 -c "
import os, re
path = os.environ['HOME'] + '/atlas-source/frontend/src/router/app.tsx'
content = open(path).read()
content = re.sub(r'<<<<<<< HEAD\n(.*?)=======\n(.*?)>>>>>>> .*?\n', r'\1\2', content, flags=re.DOTALL)
open(path, 'w').write(content)
"
    git add frontend/src/router/app.tsx
    echo "  ✅ app.tsx → birleştirildi"
  fi

  if echo "$CONFLICTS" | grep -q "master.xml"; then
    python3 -c "
import os, re
path = os.environ['HOME'] + '/atlas-source/api/src/main/resources/db/master.xml'
content = open(path).read()
content = re.sub(r'<<<<<<< HEAD\n(.*?)=======\n(.*?)>>>>>>> .*?\n', r'\1\2', content, flags=re.DOTALL)
open(path, 'w').write(content)
"
    git add api/src/main/resources/db/master.xml
    echo "  ✅ master.xml → birleştirildi"
  fi

  if echo "$CONFLICTS" | grep -q "CompanyController.java"; then
    python3 -c "
import os, re
path = os.environ['HOME'] + '/atlas-source/api/src/main/java/com/grash/controller/CompanyController.java'
content = open(path).read()
content = re.sub(r'<<<<<<< HEAD\n(.*?)=======\n(.*?)>>>>>>> .*?\n', r'\1\2', content, flags=re.DOTALL)
open(path, 'w').write(content)
"
    git add api/src/main/java/com/grash/controller/CompanyController.java
    echo "  ✅ CompanyController.java → birleştirildi"
  fi

  if echo "$CONFLICTS" | grep -q "UserController.java"; then
    python3 -c "
import os, re
path = os.environ['HOME'] + '/atlas-source/api/src/main/java/com/grash/controller/UserController.java'
content = open(path).read()
content = re.sub(r'<<<<<<< HEAD\n(.*?)=======\n(.*?)>>>>>>> .*?\n', r'\1\2', content, flags=re.DOTALL)
open(path, 'w').write(content)
"
    git add api/src/main/java/com/grash/controller/UserController.java
    echo "  ✅ UserController.java → birleştirildi"
  fi

  REMAINING=$(git diff --name-only --diff-filter=U 2>/dev/null)
  if [ -n "$REMAINING" ]; then
    echo ""
    echo "❌ Manuel çözüm gereken dosyalar:"
    echo "$REMAINING"
    echo ""
    echo "VS Code'da aç: open ~/atlas-source"
    echo "Çözdükten sonra: git add <dosya> && git rebase --continue"
    echo "Sonra tekrar çalıştır: ~/upstream-update.sh"
    exit 1
  fi

  git rebase --continue --no-edit
fi

echo ""
echo "🔄 main branch güncelleniyor..."
git checkout main
git reset --hard $BRANCH
git push origin main --force
git branch -D $BRANCH

echo ""
echo "🏗️  Docker rebuild başlıyor..."
cd ~/atlas-cmms
~/update-atlas.sh

echo ""
echo "🔑 Superadmin şifre fix..."
~/fix-superadmin.sh

echo ""
echo "✅ Tamamlandı!"
