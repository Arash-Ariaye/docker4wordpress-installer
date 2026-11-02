
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

**Developed by [Arash Ariaye](https://github.com/Arash-Ariaye)**
