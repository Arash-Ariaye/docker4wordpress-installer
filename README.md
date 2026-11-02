
# Automated Docker4WordPress Installer

A simple automated installer for [Wodby Docker4WordPress](https://github.com/wodby/docker4wordpress) on Ubuntu, featuring Traefik reverse proxy and free Let's Encrypt SSL.

## Quick Installation

```bash
curl -fsSL https://raw.githubusercontent.com/Arash-Ariaye/docker4wordpress-installer/main/install-docker4wordpress.sh -o /tmp/install.sh && sudo bash /tmp/install.sh wp.example.com
```

Replace `wp.example.com` with your actual domain.

## Features

- Automatic Docker and Docker Compose installation
- WordPress and MariaDB deployment
- Traefik reverse proxy configuration
- Free Let's Encrypt SSL certificates
- Automatic HTTP to HTTPS redirection
- Persistent database and configuration storage
- Automatic container restart policies
- AMD64 and ARM64 support

## Requirements

- Ubuntu server
- Root or sudo access
- Domain DNS pointing to your server IP
- TCP ports `80` and `443` accessible from the internet

## Service Management

```bash
cd /opt/docker4wordpress

# Check container status
docker compose ps

# View logs
docker compose logs -f

# Restart services
docker compose restart

# Update Docker images
docker compose pull
docker compose up -d
```

## Useful Links

- [Project Repository](https://github.com/Arash-Ariaye/docker4wordpress-installer)
- [Wodby Docker4WordPress](https://github.com/wodby/docker4wordpress)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Let's Encrypt](https://letsencrypt.org/)

---

**Developed by [Arash Ariaye](https://github.com/Arash-Ariaye)**


# نصب خودکار WordPress با Docker

اسکریپت نصب خودکار [Wodby Docker4WordPress](https://github.com/wodby/docker4wordpress) روی Ubuntu به همراه Traefik و گواهی SSL رایگان Let's Encrypt.

## نصب سریع

```bash
curl -fsSL https://raw.githubusercontent.com/Arash-Ariaye/docker4wordpress-installer/main/install-docker4wordpress.sh -o /tmp/install.sh && sudo bash /tmp/install.sh wp.example.com
```

به‌جای `wp.example.com` دامنه خودت را وارد کن.

## امکانات

- نصب خودکار Docker و Docker Compose
- راه‌اندازی WordPress و MariaDB
- راه‌اندازی Traefik Reverse Proxy
- دریافت و تمدید خودکار SSL از Let's Encrypt
- انتقال خودکار HTTP به HTTPS
- ذخیره‌سازی دائمی اطلاعات و تنظیمات
- پشتیبانی از Ubuntu روی معماری AMD64 و ARM64

## پیش‌نیازها

- سرور Ubuntu
- دسترسی Root یا Sudo
- تنظیم DNS دامنه روی IP سرور
- باز بودن پورت‌های TCP `80` و `443`

## مدیریت سرویس‌ها

```bash
cd /opt/docker4wordpress

# مشاهده وضعیت سرویس‌ها
docker compose ps

# مشاهده لاگ‌ها
docker compose logs -f

# راه‌اندازی مجدد
docker compose restart

# به‌روزرسانی ایمیج‌ها
docker compose pull
docker compose up -d
```

## اطلاعات بیشتر

- [GitHub Repository](https://github.com/Arash-Ariaye/docker4wordpress-installer)
- [Docker4WordPress](https://github.com/wodby/docker4wordpress)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Let's Encrypt](https://letsencrypt.org/)

---

