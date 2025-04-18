---
title: "btrfsで別マシンに定期バックアップ"
date: "2024-04-07"
tags: ["Linux", "btrfs"]
---

## はじめに

この記事は、工研新歓ブログリレー2024の6日目の記事です。

- 前回: [みみさん、自宅鯖を始めてみたら意外と面白かった](https://zenn.dev/ueckoken/articles/83a7606a8ec96d)

自宅のファイルサーバにはbtrfsを使っています。私は卒論執筆中にメイン機のSSDが壊れてしまい、研究データを載せておいたファイルサーバに助けられました。この事件の後に、万が一にもファイルサーバのデータが消えないようにスナップショットとバックアップの設定を入れることにしました。
多摩川データセンターから、福岡データセンター(実家)に定期バックアップが走っています。
この記事は、btrfsの布教がてら、別マシンに定期バックアップを取る方法を紹介します。

## btrfsのスナップショットについて

btrfsは、ファイルシステムのスナップショットを取る機能が付いています。
スナップショットは、あるタイミングのファイルシステムの中身をそのまま保存しておく機能です。
CoWファイルシステムなので、スナップショットを取ってもあんまりディスク容量を食わないのが特徴です。
`btrbk`は、btrfsのスナップショットを管理し、バックアップを取るツールです。

## btrbkのインストール

環境: 2024/04/07時点のArch Linux、バックアップ元、先は`/mnt`にbtrfsのファイルシステムをマウント。
ツール: `btrbk`

まずは、`btrbk`をインストールします。

```
$ yay -S btrbk
```

## Optional: Tailscaleのインストール

自分はバックアップ元とバックアップ先のマシンにTailscaleをインストールして通信しています。
NATを無視してVPNで繋いでくれるのでオススメです。
以降は、TailscaleのMagicDNSで、`glacier`というホスト名宛で通信できることを前提に進めます。

## SSHの設定

バックアップ元のマシンからバックアップ先のマシンに公開鍵のSSHで接続できるように設定します。
バックアップ元で公開鍵ペアを作成します。パスフレーズは空にしてください。

```
$ ssh-keygen -t ed25519 -f /etc/btrbk/ssh/id_glacier_btrbk # とりあえずここに置いてるけどいいのか？
```

公開鍵をバックアップ先のマシンにコピーします。rsyncとかコピペとかでバックアップ先のマシンのrootユーザにログインできるようにしてください。

一応、バックアップ元からバックアップ先にSSHでログインできるか確認しておきます。

```
$ ssh root@glacier -i /etc/btrbk/ssh/id_glacier_btrbk
```


## btrbkの設定

設定ファイルを作成します。
サンプルは`/etc/btrbk/btrbk.conf.example`にあります。

```
$ sudo cp /etc/btrbk/btrbk.conf.example /etc/btrbk/btrbk.conf
```

`/etc/btrbk/btrbk.conf`を編集します。コメントアウトは残ってると動かないかもしれないです。バックアップの必要数と容量とかと相談して決めてください。

```
transaction_log /var/log/btrbk.log

ssh_identity /etc/btrbk/ssh/id_glacier_btrbk
ssh_user root
stream_buffer 256m

snapshot_preserve_min   48h
# 本体のスナップショットの最小保存期間
snapshot_preserve       48h 14d 10w 2m
# 本体のスナップショットの保存期間
# この設定だと1時間おきのスナップショットを48時間、1日おきを14日、1週間おきを10週間、1ヶ月おきを2ヶ月保存する

target_preserve_min     no
# バックアップ先のスナップショットの最小保存期間、noだと無制限
target_preserve         12h 20d 10w *m
# バックアップ先のスナップショットの保存期間、1時間おきを12時間、1日おきを20日、1週間おきを10週間、1ヶ月おきを無制限保存する

archive_preserve_min    latest
# しらん
archive_preserve        12m 10y

volume /mnt/
  target send-receive ssh://glacier/mnt/hogepiyo-backups
  # バックアップ先のスナップショットを作成する親ディレクトリを指定
  subvolume live
  # バックアップ元でバックアップ対象のサブボリュームを指定、今回は`live`というサブボリュームを指定
    snapshot_dir btrbk_snapshots
    # バックアップ元でスナップショットを保存するディレクトリを指定
```

## btrbkの定期実行

ArchLinuxでは、`/usr/lib/systemd/system/btrbk.service`と`/usr/lib/systemd/system/btrbk.timer`が用意されています。が、このタイマーはdailyですが、hourlyで実行したいのでコピペして新しくタイマーを作成します。`/etc/systemd/system/btrbk-hourly.timer`と`service`を作ります

```systemd:/etc/systemd/system/btrbk-hourly.timer
[Unit]
Description=btrbk hourly backup

[Timer]
OnCalendar=hourly
AccuracySec=10min
Persistent=true

[Install]
WantedBy=timers.target
```

```systemd:/etc/systemd/system/btrbk-hourly.service
[Unit]
Description=btrbk backup
Documentation=man:btrbk(1)

[Service]
Type=oneshot
ExecStart=/usr/bin/btrbk run
```

有効化します。
```
sudo systemctl daemon-reload
sudo systemctl enable --now btrbk-hourly.timer
```

1時間おきにバックアップが取られてたら成功です。
