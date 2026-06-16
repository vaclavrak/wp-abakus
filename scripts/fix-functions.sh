#!/bin/bash
# Fix functions.php

FUNCTIONS_PHP="/var/www/wordpress/wp-content/themes/hello-theme-child-master/functions.php"

# Remove broken lines
sed -i '/require_once __DIR__ . $/d' "$FUNCTIONS_PHP"
sed -i '/\/\/ Custom fonts fix/d' "$FUNCTIONS_PHP"
sed -i '/require_once __DIR__ . \/custom-fonts.php;/d' "$FUNCTIONS_PHP"

# Check if correct require exists
if ! grep -q "custom-fonts.php" "$FUNCTIONS_PHP"; then
    echo "" >> "$FUNCTIONS_PHP"
    echo "// Custom fonts fix" >> "$FUNCTIONS_PHP"
    echo "require_once __DIR__ . '/custom-fonts.php';" >> "$FUNCTIONS_PHP"
    echo "Added custom fonts require"
else
    echo "Custom fonts require already exists"
fi

# Verify
echo "Last 5 lines of functions.php:"
tail -5 "$FUNCTIONS_PHP"