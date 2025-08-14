#!/bin/bash
echo "running..."
service_content=$(cat <<'EOF'
[Unit]
Description=$DESCRIPTION
After=network.target

[Service]
ExecStart=/usr/local/bin/myscript.sh
Restart=always
RestartSec=5
User=myuser
WorkingDirectory=/home/myuser

[Install]
WantedBy=multi-user.target
EOF
)
read -p "enter service path:" SVCPATH
if [ ! -f $SVCPATH ]; then
    echo "Invalid. File doesn't exist."
    exit
else
    echo "$service_content" | sudo tee /etc/systemd/system/myscript.service
fi
