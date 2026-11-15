<?php
// Gera o wp-config.php do laboratorio a partir do wp-config-sample.php,
// com o banco vindo de variaveis de ambiente e chaves/salts aleatorios.
$cfg = file_get_contents('/var/www/html/wp-config-sample.php');

$valores = [
    'DB_NAME'     => getenv('DB_NAME'),
    'DB_USER'     => getenv('DB_USER'),
    'DB_PASSWORD' => getenv('DB_PASSWORD'),
    'DB_HOST'     => getenv('DB_HOST'),
];
foreach (['AUTH_KEY', 'SECURE_AUTH_KEY', 'LOGGED_IN_KEY', 'NONCE_KEY',
          'AUTH_SALT', 'SECURE_AUTH_SALT', 'LOGGED_IN_SALT', 'NONCE_SALT'] as $k) {
    $valores[$k] = bin2hex(random_bytes(32));
}
foreach ($valores as $chave => $valor) {
    $cfg = preg_replace(
        "/define\(\s*'" . $chave . "',\s*'[^']*'\s*\);/",
        "define( '" . $chave . "', '" . addslashes((string) $valor) . "' );",
        $cfg
    );
}

// Object cache: o Service "redis" do mesmo namespace (plugin Redis Object Cache).
$extra = "define( 'WP_REDIS_HOST', 'redis' );\n"
       . "define( 'DISALLOW_FILE_EDIT', true );\n";
$cfg = str_replace("/* That's all, stop editing!", $extra . "\n/* That's all, stop editing!", $cfg);
$cfg = str_replace("/* Isto é tudo, pode parar de editar!", $extra . "\n/* Isto é tudo, pode parar de editar!", $cfg);

echo $cfg;
