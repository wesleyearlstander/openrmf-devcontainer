#!/bin/bash -e

USER_ID=$(id -u)
GROUP_ID=$(id -g)

sudo usermod -u $USER_ID -o -m -d /home/developer developer > /dev/null 2>&1
sudo groupmod -g $GROUP_ID developer > /dev/null 2>&1
sudo chown -R developer:developer /workspaces

ln -sfn /home/developer/.vscode /workspaces/.vscode

rm -f /workspaces/compile_flags.txt || true
sed -e 's@\$ROS_DISTRO@'"$ROS_DISTRO"'@' /home/developer/compile_flags.txt > /workspaces/compile_flags.txt

ln -sfn /workspaces /home/developer/workspaces

source /opt/ros/$ROS_DISTRO/setup.bash

mkdir -p /workspaces/workspace/src

cd /home/developer

exec $@
