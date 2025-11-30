#!/bin/bash
# WordPress Performance Benchmark Script
# Tests: CPU, Memory, Disk I/O, MySQL, PHP, Network

OUTPUT_FILE="/tmp/benchmark_results.json"

echo "Starting WordPress Performance Benchmark..."
echo "============================================"

# Get server info
HOSTNAME=$(hostname)
CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
CPU_CORES=$(nproc)
TOTAL_RAM=$(free -m | awk '/Mem:/ {print $2}')
ARCHITECTURE=$(uname -m)

echo "Server: $HOSTNAME"
echo "CPU: $CPU_MODEL ($CPU_CORES cores)"
echo "RAM: ${TOTAL_RAM}MB"
echo "Architecture: $ARCHITECTURE"
echo ""

# 1. CPU Benchmark - Single thread (WordPress is mostly single-threaded)
echo "=== CPU Single-Thread Test (sysbench) ==="
CPU_SINGLE=$(sysbench cpu --cpu-max-prime=20000 --threads=1 run 2>/dev/null | grep "events per second" | awk '{print $4}')
echo "CPU Single-thread: $CPU_SINGLE events/sec"

# 2. CPU Benchmark - Multi-thread
echo "=== CPU Multi-Thread Test (sysbench) ==="
CPU_MULTI=$(sysbench cpu --cpu-max-prime=20000 --threads=$CPU_CORES run 2>/dev/null | grep "events per second" | awk '{print $4}')
echo "CPU Multi-thread: $CPU_MULTI events/sec"

# 3. Memory Benchmark
echo "=== Memory Test (sysbench) ==="
MEM_SPEED=$(sysbench memory --memory-block-size=1K --memory-total-size=10G --threads=1 run 2>/dev/null | grep "transferred" | awk '{print $4}' | tr -d '(')
echo "Memory Speed: $MEM_SPEED MB/sec"

# 4. Disk I/O - Sequential Write
echo "=== Disk I/O Test (dd) ==="
DISK_WRITE=$(dd if=/dev/zero of=/tmp/testfile bs=1M count=1024 conv=fdatasync 2>&1 | grep -oP '\d+(\.\d+)? [MG]B/s' | head -1)
rm -f /tmp/testfile
echo "Disk Write: $DISK_WRITE"

# Extract numeric value for JSON
DISK_WRITE_NUM=$(echo "$DISK_WRITE" | grep -oP '[\d.]+')
DISK_WRITE_UNIT=$(echo "$DISK_WRITE" | grep -oP '[MG]B')
if [ "$DISK_WRITE_UNIT" = "GB" ]; then
    DISK_WRITE_MB=$(echo "$DISK_WRITE_NUM * 1024" | bc)
else
    DISK_WRITE_MB=$DISK_WRITE_NUM
fi

# 5. Disk I/O - Random Read/Write (important for WordPress/MySQL)
echo "=== Disk Random I/O Test (sysbench) ==="
sysbench fileio --file-total-size=2G prepare >/dev/null 2>&1
DISK_RANDOM=$(sysbench fileio --file-total-size=2G --file-test-mode=rndrw --time=30 --max-requests=0 run 2>/dev/null | grep "read, MiB/s" | awk '{print $3}')
DISK_RANDOM_WRITE=$(sysbench fileio --file-total-size=2G --file-test-mode=rndrw --time=30 --max-requests=0 run 2>/dev/null | grep "written, MiB/s" | awk '{print $3}')
sysbench fileio --file-total-size=2G cleanup >/dev/null 2>&1
echo "Disk Random Read: $DISK_RANDOM MiB/s"

# 6. MySQL/MariaDB Benchmark
echo "=== MySQL Benchmark ==="
# Install and configure MySQL for testing
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq mariadb-server >/dev/null 2>&1
systemctl start mariadb
systemctl enable mariadb >/dev/null 2>&1

# Create test database
mysql -e "CREATE DATABASE IF NOT EXISTS benchmark_test;"
mysql -e "CREATE USER IF NOT EXISTS 'benchmark'@'localhost' IDENTIFIED BY 'benchmark123';"
mysql -e "GRANT ALL PRIVILEGES ON benchmark_test.* TO 'benchmark'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Prepare sysbench for MySQL
sysbench /usr/share/sysbench/oltp_read_write.lua --mysql-host=localhost --mysql-user=benchmark --mysql-password=benchmark123 --mysql-db=benchmark_test --tables=10 --table-size=10000 prepare >/dev/null 2>&1

# Run MySQL benchmark
MYSQL_RESULT=$(sysbench /usr/share/sysbench/oltp_read_write.lua --mysql-host=localhost --mysql-user=benchmark --mysql-password=benchmark123 --mysql-db=benchmark_test --tables=10 --table-size=10000 --threads=4 --time=60 run 2>/dev/null)
MYSQL_TPS=$(echo "$MYSQL_RESULT" | grep "transactions:" | awk '{print $3}' | tr -d '(')
MYSQL_QPS=$(echo "$MYSQL_RESULT" | grep "queries:" | awk '{print $3}' | tr -d '(')
MYSQL_LATENCY=$(echo "$MYSQL_RESULT" | grep "avg:" | awk '{print $2}')

echo "MySQL TPS: $MYSQL_TPS"
echo "MySQL QPS: $MYSQL_QPS"
echo "MySQL Latency: ${MYSQL_LATENCY}ms"

# Cleanup
sysbench /usr/share/sysbench/oltp_read_write.lua --mysql-host=localhost --mysql-user=benchmark --mysql-password=benchmark123 --mysql-db=benchmark_test cleanup >/dev/null 2>&1

# 7. PHP Benchmark
echo "=== PHP Benchmark ==="
apt-get install -y -qq php php-cli php-mysql php-mbstring php-xml php-curl >/dev/null 2>&1

# PHP computation benchmark
PHP_BENCH=$(php -r '
$start = microtime(true);
$iterations = 1000000;
$result = 0;
for ($i = 0; $i < $iterations; $i++) {
    $result += sqrt($i) * sin($i) * cos($i);
    $str = md5(strval($i));
    $arr = explode("a", $str);
}
$time = microtime(true) - $start;
echo round($iterations / $time, 2);
')
echo "PHP Operations/sec: $PHP_BENCH"

# PHP WordPress-like operations (string processing, array operations)
PHP_WP_BENCH=$(php -r '
$start = microtime(true);
$iterations = 50000;
for ($i = 0; $i < $iterations; $i++) {
    $content = str_repeat("Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", 50);
    $content = preg_replace("/ipsum/", "IPSUM", $content);
    $content = strip_tags("<p>" . $content . "</p>");
    $words = explode(" ", $content);
    $words = array_filter($words, function($w) { return strlen($w) > 3; });
    $content = implode(" ", $words);
    $hash = password_hash(substr($content, 0, 72), PASSWORD_DEFAULT);
}
$time = microtime(true) - $start;
echo round($iterations / $time, 2);
')
echo "PHP WordPress-like ops/sec: $PHP_WP_BENCH"

# 8. Network Latency Test
echo "=== Network Test ==="
PING_EU=$(ping -c 5 google.de 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
echo "Ping to EU (google.de): ${PING_EU}ms"

# 9. Redis Benchmark (common WordPress cache)
echo "=== Redis Benchmark ==="
apt-get install -y -qq redis-server >/dev/null 2>&1
systemctl start redis-server
REDIS_BENCH=$(redis-benchmark -q -n 100000 -c 50 -P 12 2>/dev/null | grep "SET:" | awk '{print $2}')
echo "Redis SET ops/sec: $REDIS_BENCH"

# 10. Concurrent connections test (simulating WordPress traffic)
echo "=== Concurrent Connections Test ==="
apt-get install -y -qq nginx >/dev/null 2>&1
systemctl start nginx

# Install wrk for HTTP benchmark
apt-get install -y -qq wrk >/dev/null 2>&1 || {
    cd /tmp
    apt-get install -y -qq build-essential libssl-dev git >/dev/null 2>&1
    git clone https://github.com/wg/wrk.git >/dev/null 2>&1
    cd wrk && make -j$(nproc) >/dev/null 2>&1
    cp wrk /usr/local/bin/
}

WRK_RESULT=$(wrk -t4 -c100 -d30s http://localhost/ 2>/dev/null)
HTTP_RPS=$(echo "$WRK_RESULT" | grep "Requests/sec" | awk '{print $2}')
HTTP_LATENCY=$(echo "$WRK_RESULT" | grep "Latency" | awk '{print $2}')
echo "HTTP Requests/sec: $HTTP_RPS"
echo "HTTP Latency: $HTTP_LATENCY"

# Convert latency to ms for comparison
HTTP_LATENCY_MS=$(echo "$HTTP_LATENCY" | grep -oP '[\d.]+')
if echo "$HTTP_LATENCY" | grep -q "us"; then
    HTTP_LATENCY_MS=$(echo "scale=3; $HTTP_LATENCY_MS / 1000" | bc)
fi

echo ""
echo "============================================"
echo "Benchmark Complete!"
echo "============================================"

# Generate JSON output
cat > $OUTPUT_FILE << EOF
{
  "hostname": "$HOSTNAME",
  "cpu_model": "$CPU_MODEL",
  "cpu_cores": $CPU_CORES,
  "ram_mb": $TOTAL_RAM,
  "architecture": "$ARCHITECTURE",
  "results": {
    "cpu_single_thread": ${CPU_SINGLE:-0},
    "cpu_multi_thread": ${CPU_MULTI:-0},
    "memory_mb_sec": ${MEM_SPEED:-0},
    "disk_write_mb_sec": ${DISK_WRITE_MB:-0},
    "disk_random_read_mb_sec": ${DISK_RANDOM:-0},
    "mysql_tps": ${MYSQL_TPS:-0},
    "mysql_qps": ${MYSQL_QPS:-0},
    "mysql_latency_ms": ${MYSQL_LATENCY:-0},
    "php_ops_sec": ${PHP_BENCH:-0},
    "php_wp_ops_sec": ${PHP_WP_BENCH:-0},
    "redis_ops_sec": ${REDIS_BENCH:-0},
    "http_rps": ${HTTP_RPS:-0},
    "ping_eu_ms": ${PING_EU:-0}
  }
}
EOF

cat $OUTPUT_FILE
