const fs = require('fs');
const path = require('path');

const MIGRATIONS_DIR = path.join(__dirname, '../supabase/migrations');
const BACKUP_DIR = path.join(__dirname, '../supabase/migrations_test_data');

const TEST_FILES = [
  '20251110220256_seed_initial_data.sql',
  '20251110223529_add_mock_technicians.sql',
  '20260127015523_seed_vendor_payment_test_data.sql'
];

const action = process.argv[2]; // 'clean' or 'dev'

if (!fs.existsSync(BACKUP_DIR)) {
  fs.mkdirSync(BACKUP_DIR, { recursive: true });
}

if (action === 'clean') {
  console.log('Preparing for CLEAN deployment (hiding test data)...');
  TEST_FILES.forEach(file => {
    const src = path.join(MIGRATIONS_DIR, file);
    const dest = path.join(BACKUP_DIR, file);
    if (fs.existsSync(src)) {
      fs.renameSync(src, dest);
      console.log(`Moved ${file} to backup.`);
    } else {
      console.log(`File ${file} not found in migrations (already moved?).`);
    }
  });
  console.log('Done. You can now run "supabase db push".');
} else if (action === 'dev') {
  console.log('Restoring TEST data for development...');
  TEST_FILES.forEach(file => {
    const src = path.join(BACKUP_DIR, file);
    const dest = path.join(MIGRATIONS_DIR, file);
    if (fs.existsSync(src)) {
      fs.renameSync(src, dest);
      console.log(`Restored ${file}.`);
    } else {
      console.log(`File ${file} not found in backup (already restored?).`);
    }
  });
  console.log('Done. Development environment restored.');
} else {
  console.log('Usage: node toggle_clean_deploy.js [clean|dev]');
}
