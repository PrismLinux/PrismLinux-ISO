FROM archlinux:latest

RUN pacman -Sy --noconfirm \
  archiso \
  git \
  base-devel \
  sudo \
  arch-install-scripts \
  dosfstools \
  e2fsprogs \
  erofs-utils \
  libarchive \
  libisoburn \
  mtools \
  grub \
  squashfs-tools && \
  pacman -Scc --noconfirm

RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
  locale-gen && \
  echo "LANG=en_US.UTF-8" > /etc/locale.conf && \
  ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# Optional: create non-root user for other tasks
RUN useradd -m -G wheel -s /bin/bash builder && \
  echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder && \
  chmod 0440 /etc/sudoers.d/builder

# Do not drop to non-root: mkarchiso needs root anyway
WORKDIR /workspace

ENTRYPOINT [ "/bin/bash" ]
