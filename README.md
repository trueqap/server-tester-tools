# Server Tester Tools

A comprehensive server benchmark script for testing VPS and cloud server performance.

## Features

- **CPU Benchmark** - Single-thread and multi-thread performance (sysbench)
- **Memory Benchmark** - Memory bandwidth test
- **Disk I/O** - Sequential write and random read/write tests
- **MySQL/MariaDB** - OLTP benchmark with transactions per second
- **PHP Performance** - Computation and WordPress-like operations
- **Redis** - Cache performance benchmark
- **HTTP** - Concurrent connections test with nginx + wrk
- **Network** - Latency test

## Quick Start

Run directly on your server:

```bash
curl -sL https://raw.githubusercontent.com/trueqap/server-tester-tools/main/benchmark.sh | sudo bash
```

Or download and run:

```bash
wget https://raw.githubusercontent.com/trueqap/server-tester-tools/main/benchmark.sh
chmod +x benchmark.sh
sudo ./benchmark.sh
```

## Requirements

- Ubuntu/Debian based system
- Root access (sudo)
- Internet connection (for package installation)

The script will automatically install required packages:
- sysbench
- bc
- mariadb-server
- php + php-cli
- redis-server
- nginx
- wrk

## Output

Results are displayed in the terminal and saved to `/tmp/benchmark_results.json` in JSON format.

Example output:
```json
{
  "hostname": "server-name",
  "cpu_model": "AMD EPYC Genoa",
  "cpu_cores": 4,
  "ram_mb": 8192,
  "architecture": "x86_64",
  "results": {
    "cpu_single_thread": 1645,
    "cpu_multi_thread": 6572,
    "memory_mb_sec": 6484,
    "disk_write_mb_sec": 732,
    "mysql_tps": 833,
    "php_ops_sec": 2730000,
    "http_rps": 45491
  }
}
```

## Tested On

- DigitalOcean Droplets
- AWS EC2
- Vultr
- Linode
- Any Ubuntu/Debian VPS

## License

MIT License - feel free to use and modify.

## Contributing

Pull requests welcome! Please test on multiple server types before submitting.
