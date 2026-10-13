#!/usr/bin/env bash
set -uo pipefail

PREFIX=gubaydullin-09
APP_PORT=8027
RESULT=0

echo "==> проверка балансировщика"

LB_IP=$(yc load-balancer network-load-balancer get --name "$PREFIX-lb" \
 --format json 2>/dev/null | jq -r '.listeners[0].address // empty' || true)

if [ -n "$LB_IP" ]; then
 HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://$LB_IP" || true)
else
 HTTP_CODE=000
fi

if [ "$HTTP_CODE" = "200" ]; then
 echo "✓ балансировщик отвечает: 200"
else
 echo "✗ балансировщик не отвечает: $HTTP_CODE"
 RESULT=1
fi

echo "==> проверка распределения"

HOSTS=""
if [ -n "$LB_IP" ]; then
 for i in $(seq 1 10); do
  HOST=$(curl -s --max-time 5 "http://$LB_IP" \
   | sed -n 's/^cloudlab on //p' || true)
  if [ -n "$HOST" ]; then
   HOSTS="${HOSTS}${HOST}"$'\n'
  fi
 done
fi

UNIQUE_HOSTS=$(printf '%s' "$HOSTS" | sort -u | sed '/^$/d')
HOST_COUNT=$(printf '%s\n' "$UNIQUE_HOSTS" | sed '/^$/d' | wc -l | tr -d ' ')

if [ "$HOST_COUNT" -gt 1 ]; then
 echo "✓ ответили машины: $(printf '%s' "$UNIQUE_HOSTS" | tr '\n' ' ')"
else
 echo "✗ ответила только одна машина или ни одной"
 RESULT=1
fi

echo "==> проверка сервера приложения"

APP_IP=$(yc compute instance get "$PREFIX-app-1" --format json 2>/dev/null \
 | jq -r '.network_interfaces[0].primary_v4_address.address // empty' || true)

WEB_IP=$(yc compute instance get "$PREFIX-web-1" --format json 2>/dev/null \
 | jq -r '.network_interfaces[0].primary_v4_address.one_to_one_nat.address // empty' || true)

APP_CODE=""
if [ -n "$APP_IP" ] && [ -n "$WEB_IP" ]; then
 APP_CODE=$(ssh \
  -o BatchMode=yes \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ConnectTimeout=5 \
  student@"$WEB_IP" \
  "curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://$APP_IP:$APP_PORT" \
  2>/dev/null || true)
fi

if [ "$APP_CODE" = "200" ]; then
 echo "✓ сервер приложения доступен с web-1: 200"
else
 echo "✗ сервер приложения недоступен с web-1"
 RESULT=1
fi

exit "$RESULT"
