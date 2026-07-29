# shellcheck shell=sh
# /etc/profile.d/10-s25-desktop.sh — يُحمّل بيئة نظام S25 Desktop
if [ -r /opt/s25/etc/env.sh ]; then
    . /opt/s25/etc/env.sh
fi
case ":$PATH:" in
    *":/opt/s25/bin:"*) ;;
    *) PATH="/opt/s25/bin:$PATH"; export PATH ;;
esac
