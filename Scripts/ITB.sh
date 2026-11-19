#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
#
# ITB(UBI) 编译线补丁，由 Scripts/Settings.sh 在 ./wrt/ 目录下 source。
#
# 目的：在 bingoguo93/immortalwrt 6.18 上补出 Device/nokia_xg-140g-tf-ubi，
#      产出 fitblk 解包的 UBI sysupgrade.itb（网页 U-Boot / UBI 分区体系）。
#      上游 6.18 已自带 040g-tf-ubi 的 DTS 依赖、02_network 分支与
#      nokia_xg-040g-md-ubi-images 镜像宏，唯独缺 140G-TF 的 DTS 和设备条目。
#
# 生效条件：WRT_CONFIG 名称含 ITB 且平台为 airoha，其它编译线零影响。

if [[ "${WRT_CONFIG,,}" != *itb* ]]; then
	return 0
fi

if [[ "${WRT_TARGET,,}" != *airoha* ]]; then
	echo "ITB: 非 airoha 平台，跳过"
	return 0
fi

if [ ! -d target/linux/airoha ]; then
	echo "ITB: 未找到 target/linux/airoha，跳过"
	return 0
fi

DTS="target/linux/airoha/dts/an7581-nokia_xg-140g-tf-ubi.dts"
MK="target/linux/airoha/image/an7581.mk"
NW="target/linux/airoha/an7581/base-files/etc/board.d/02_network"
PLAT="target/linux/airoha/an7581/base-files/lib/upgrade/platform.sh"

# ---------------------------------------------------------------- 1. DTS
if [ ! -f "$DTS" ]; then
	cat > "$DTS" <<'WRT_DTS'
// SPDX-License-Identifier: GPL-2.0-only OR MIT

#include "an7581-nokia_xg-040g-tf-common.dtsi"
#include "an758x-nokia_xg-040g-ubi-parts.dtsi"

/ {
	model = "XG-140G-TF";
	compatible = "nokia,xg-140g-tf-ubi", "airoha,an7581",
		     "airoha,en7581";
};
WRT_DTS
	echo "ITB: 已生成 ${DTS##*/}"
else
	echo "ITB: DTS 已存在，跳过"
fi

# ------------------------------------------------------- 2. 02_network 兜底
# 6.18 已预留 nokia,xg-140g-tf-ubi（4LAN + pon0），仅在缺失时补上。
if [ -f "$NW" ] && ! grep -q "nokia,xg-140g-tf-ubi" "$NW"; then
	sed -i 's/nokia,xg-040g-md-ubi)/nokia,xg-040g-md-ubi |\\\n\tnokia,xg-140g-tf-ubi)/' "$NW"
	echo "ITB: 已补 02_network 分支"
fi

# ------------------------------------------------------ 3. platform.sh 升级路径
# 缺这一步的后果：sysupgrade 会落到 *) nand_do_upgrade，把 .itb 当 tar 解包而失败。
# 需要把 nokia,xg-140g-tf-ubi 同时挂进 fit_check_image 与 fit_do_upgrade 两个分支。
if [ -f "$PLAT" ] && ! grep -q "nokia,xg-140g-tf-ubi" "$PLAT"; then
	sed -i 's/nokia,xg-040g-md-ubi|\\/nokia,xg-040g-md-ubi|\\\n\t\tnokia,xg-140g-tf-ubi|\\/' "$PLAT"
	echo "ITB: 已给 platform.sh 补 fit_check_image / fit_do_upgrade 分支"
fi

# ------------------------------------------------------ 4. 设备定义（.itb）
if [ -f "$MK" ] && ! grep -q "Device/nokia_xg-140g-tf-ubi" "$MK"; then
	cat >> "$MK" <<'WRT_MK'

define Device/nokia_xg-140g-tf-ubi
  $(call Device/nokia_xg-040g-tf-common)
  DEVICE_MODEL := XG-140G-TF
  DEVICE_VARIANT := (UBI)
  DEVICE_DTS := an7581-nokia_xg-140g-tf-ubi
  $(call Device/nokia_xg-040g-md-ubi-images)
endef
TARGET_DEVICES += nokia_xg-140g-tf-ubi
WRT_MK
	echo "ITB: 已追加 Device/nokia_xg-140g-tf-ubi"
else
	echo "ITB: 设备条目已存在，跳过"
fi

# ------------------------------------------- 4.5 Tailscale 换成 GuNanOvO 精简版
# feeds 自带的 tailscale 体积偏大；这里换成 GuNanOvO/openwrt-tailscale 的 UPX 版。
# 它仍是源码编译（Go + feeds/packages/lang/golang），Go 版本过老会失败；
# 一旦失败，注释掉本段即自动回退官方 tailscale。
if [ -d feeds/packages ]; then
	rm -rf ./package/feeds/packages/tailscale ./package/tailscale
	if git clone --depth=1 --single-branch "https://github.com/GuNanOvO/openwrt-tailscale.git" ./gn-ts >/dev/null 2>&1; then
		cp -r ./gn-ts/package/tailscale ./package/tailscale
		rm -rf ./gn-ts
		# luci-app-tailscale（asvow）自带 /etc/config/tailscale 与 /etc/init.d/tailscale，
		# 与 GuNanOvO 包写同一路径，package/install 阶段会报
		#   ERROR: luci-app-tailscale: trying to overwrite etc/config/tailscale owned by tailscale
		# 这里让 LuCI 应用独占这两个文件，GuNanOvO 包只提供 tailscaled 二进制。
		TS_MK="package/tailscale/Makefile"
		if [ -f "$TS_MK" ]; then
			sed -i '\#files/tailscale\.init#d; \#files/tailscale\.conf#d' "$TS_MK"
			sed -i '\#^/etc/config/tailscale$#d' "$TS_MK"
			echo "ITB: 已移除 GuNanOvO 包的 init/config 安装行（改由 luci-app-tailscale 提供）"
		fi
		echo "ITB: tailscale 已替换为 GuNanOvO 精简版"
	else
		echo "ITB: 克隆 GuNanOvO/openwrt-tailscale 失败，回退官方 tailscale"
		./scripts/feeds install tailscale >/dev/null 2>&1 || echo "ITB: 回退安装同样失败，请检查 feeds/packages 里的 tailscale"
	fi
fi

# ------------------------------------------------ 4.6 honk feed + 内核 BTF
# 对调开关：换回 OpenClash 时把下面改成 0，并把 GENERAL 里 honk 两行换成 openclash。
ITB_HONK=1

if [ "$ITB_HONK" = "1" ]; then
	# honk 与 v2ray-geodata 各在一个 feed 里，源码树默认没有，需要补进 feeds.conf。
	[ -f feeds.conf ] || cp feeds.conf.default feeds.conf
	if ! grep -q "openwrt-honk" feeds.conf; then
		echo "src-git honk https://github.com/kenzok8/openwrt-honk" >> feeds.conf
		echo "src-git small https://github.com/kenzok8/small" >> feeds.conf
	fi
	./scripts/feeds update honk small || echo "ITB: honk/small feed 更新失败"
	./scripts/feeds install -a -p honk || echo "ITB: honk 包安装失败"
	# 只要 GeoIP/GeoSite 数据包，避免 whole small feed 带来同名包冲突
	./scripts/feeds install -p small v2ray-geoip v2ray-geosite >/dev/null 2>&1 \
		|| ./scripts/feeds install -a -p small >/dev/null 2>&1

	# ------------------------------------------------------------
	# 预下载 honk / doona 资产：openwrt 的下载没有超时，GitHub release
	# 握手一卡就无限等（表现为某行停半小时以上、没有 Error）。这里用带
	# 超时的 curl 提前放进 dl/，compile 阶段就完全不联网。
	DL_DIR="./dl"
	mkdir -p "$DL_DIR"
	HONK_MK="feeds/honk/honk/Makefile"
	DOONA_MK="feeds/honk/luci-app-honk/Makefile"
	if [ -f "$HONK_MK" ] && [ -f "$DOONA_MK" ]; then
		HONK_TAG=$(sed -n 's/^HONK_SOURCE_TAG?=//p' "$HONK_MK" | head -1)
		CORE_COMMIT=$(sed -n 's/^CORE_COMMIT:=//p' "$HONK_MK" | head -1)
		HONK_ASSET="honk-core-${CORE_COMMIT}-aarch64.tar.gz"
		DOONA_ASSET=$(sed -n 's/^PKG_SOURCE:=//p' "$DOONA_MK" | head -1)
		HONK_BASE="https://github.com/kenzok8/openwrt-honk/releases/download/${HONK_TAG}"
		for ITEM in "${HONK_ASSET}|${HONK_BASE}/${HONK_ASSET}" "${DOONA_ASSET}|${HONK_BASE}/${DOONA_ASSET}"; do
			NAME="${ITEM%%|*}"
			URL="${ITEM#*|}"
			[ -n "$NAME" ] || continue
			[ -s "$DL_DIR/$NAME" ] && continue
			if curl -fL --retry 3 --retry-delay 5 --connect-timeout 20 --max-time 600 \
				-o "$DL_DIR/$NAME.part" "$URL"; then
				mv -f "$DL_DIR/$NAME.part" "$DL_DIR/$NAME"
				echo "ITB: 预下载完成 $NAME"
			else
				rm -f "$DL_DIR/$NAME.part"
				echo "ITB: 预下载失败 $NAME（交给 make 自己下）"
			fi
		done
	fi

	# 内核 BTF：honk 启动检查硬性要求 /sys/kernel/btf/vmlinux
	echo "CONFIG_KERNEL_DEBUG_INFO=y" >> .config
	echo "CONFIG_KERNEL_DEBUG_INFO_REDUCED=n" >> .config
	echo "CONFIG_KERNEL_DEBUG_INFO_BTF=y" >> .config

	# bpffs：eBPF map 只能固定在 /sys/fs/bpf，自精简固件要确保挂上
	UDEF_DIR="package/base-files/files/etc/uci-defaults"
	mkdir -p "$UDEF_DIR"
	cat > "$UDEF_DIR/99-bpffs" <<'WRT_BPFFS'
#!/bin/sh
grep -q " /sys/fs/bpf " /proc/mounts || mount -t bpf bpf /sys/fs/bpf 2>/dev/null
grep -q " /sys/fs/bpf bpf " /etc/fstab || echo "bpf /sys/fs/bpf bpf defaults 0 0" >> /etc/fstab
exit 0
WRT_BPFFS
	chmod +x "$UDEF_DIR/99-bpffs"
	echo "ITB: honk + v2ray-geodata + 内核 BTF + bpffs 已就绪"
fi

# ------------------------------------------------- 4.7 root 免密登录
# LuCI：首次启动把 root 密码清空，登录页直接点「登录」即可
# SSH ：dropbear 默认拒绝空密码，必须在启动参数里加 -B
UDEF_DIR="package/base-files/files/etc/uci-defaults"
mkdir -p "$UDEF_DIR"
cat > "$UDEF_DIR/99-root-nopass" <<'WRT_NOPASS'
#!/bin/sh
# root 空密码：LuCI 直接登录，SSH 由 dropbear -B 放行
passwd -d root 2>/dev/null
sed -i 's/^root:[^:]*:/root::/' /etc/shadow
exit 0
WRT_NOPASS
chmod +x "$UDEF_DIR/99-root-nopass"

DB_INIT="package/network/services/dropbear/files/dropbear.init"
if [ -f "$DB_INIT" ] && ! grep -q 'pid_file" -B' "$DB_INIT"; then
	sed -i 's|procd_set_param command "\$PROG" -F -P "\$pid_file"|procd_set_param command "\$PROG" -F -P "\$pid_file" -B|' "$DB_INIT"
	echo "ITB: dropbear 已加 -B（允许空密码）"
fi
echo "ITB: root 免密登录已就绪"

# ---------------------------------------------------------- 5. 勾选设备符号
# 必须在 make defconfig 之前写入 .config
if ! grep -q "CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_nokia_xg-140g-tf-ubi=y" .config; then
	echo "CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_nokia_xg-140g-tf-ubi=y" >> .config
	echo "ITB: 已勾选 nokia_xg-140g-tf-ubi"
fi

# 只出 sysupgrade.itb：GENERAL.txt 里的 INITRAMFS=n 保持不动。
# 若同时需要 -initramfs-recovery.itb，在 make defconfig 前追加
#   echo "CONFIG_TARGET_ROOTFS_INITRAMFS=y" >> .config

echo "ITB: 补丁完成，产物为 UBI/fitblk 体系的 sysupgrade.itb"
echo "ITB: 适用于已刷网页 U-Boot（UBI 带 fip/ubootenv/fit 卷）的机器；日常升级只用 sysupgrade.itb"
