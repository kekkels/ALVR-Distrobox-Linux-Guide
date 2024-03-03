#!/bin/bash

source ./env.sh
source ./helper-functions.sh

if [[ -z "$prefix" ]]; then
   echor "No prefix found inside distrobox, aborting"
   exit 1
fi

echor "Phase 4"
export STEP_INDEX=1
cd "$prefix" || {
   echor "Couldn't go into installation folder on phase 4, aborting."
   exit 1
}

GPU=$(jq -r '.gpu' specs.json || exit 1)
AUDIO_SYSTEM=$(jq -r '.audio' specs.json || exit 1)
MULTI_GPU=$(jq -r '.multi_gpu' specs.json || exit 1)

echog "Installing packages for base functionality."
sudo pacman -q --noprogressbar -Syu git vim base-devel noto-fonts xdg-user-dirs fuse libx264 sdl2 libva-utils xorg-server --noconfirm || exit 1

echog "Installing paru-bin"
git clone https://aur.archlinux.org/paru-bin.git
cd paru-bin || echor "Couldn't go into paru-bin folder, aborting."
makepkg --noprogressbar -si --noconfirm || exit 1
cd ..

echog "Installing steam, audio and driver packages."
if [[ "$GPU" == "amd" ]]; then
   sudo pacman -q --noprogressbar -Syu libva-mesa-driver vulkan-radeon lib32-vulkan-radeon lib32-libva-mesa-driver --noconfirm || exit 1
elif [[ "$GPU" == "nvidia" ]]; then
   echog "Using host system driver mounts, not installing nvidia drivers."
   if [[ "$MULTI_GPU" == "1" ]]; then
      echog "But installing prime-run for running steamvr, games on your DGPU."
      sudo pacman -q --noprogressbar -Syu prime-run --noconfirm --assume-installed nvidia-utils || exit 1
   fi
elif [[ "$GPU" == "intel" ]]; then
   sudo pacman -q --noprogressbar -Syu libva-mesa-driver vulkan-intel lib32-vulkan-intel lib32-libva-mesa-driver --noconfirm || exit 1
   # Thanks marioeatsdirt for tip!
   echog "Installing older vulkan-intel driver as newest one (24.0 at the moment of writing) doesnt work on Intel."
   sudo pacman --noprogressbar -U \
      https://archive.archlinux.org/packages/v/vulkan-intel/vulkan-intel-23.1.4-2-x86_64.pkg.tar.zst \
      https://archive.archlinux.org/packages/l/lib32-vulkan-intel/lib32-vulkan-intel-23.1.4-2-x86_64.pkg.tar.zst --noconfirm || exit 1
else
   echor "Unknown gpu - $GPU, exiting!"
   exit 1
fi
if [[ "$AUDIO_SYSTEM" == "pipewire" ]]; then
   sudo pacman -q --noprogressbar -Syu lib32-pipewire pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber --noconfirm || exit 1
elif [[ "$AUDIO_SYSTEM" == "pulseaudio" ]]; then
   sudo pacman -q --noprogressbar -Syu pulseaudio pusleaudio-alsa --noconfirm || exit 1
else
   echor "Couldn't determine audio system: $AUDIO_SYSTEM, you may have issues with audio!"
fi

sudo pacman -q --noprogressbar -Syu steam --noconfirm --assume-installed vulkan-driver --assume-installed lib32-vulkan-driver || exit 1

export STEP_INDEX=2
sleep 2

echog "Installed base packages and Steam. Opening steam. Please install SteamVR from it."

# Define proper steam desktop file
mkdir ~/.config
xdg-mime default steam.desktop x-scheme-handler/steam

steam steam://install/250820 &>/dev/null &
echog "Installation will continue when steamvr will be installed"
while [ ! -f "$HOME/.steam/steam/steamapps/common/SteamVR/bin/vrwebhelper/linux64/vrwebhelper.sh" ]; do
   sleep 5
done
sleep 3

# todo: make this step automatic (protonup(+qt) doesn't have api for generic tools)
echog "Installing SteamPlay-None for use with SteamVR."
echor "Please set it as compatibility option in SteamVR options after Steam restart!"
mkdir -p "$HOME/.steam/steam/compatibilitytools.d"
wget https://github.com/Scrumplex/Steam-Play-None/archive/refs/heads/main.tar.gz
tar xzf main.tar.gz -C "$HOME/.steam/steam/compatibilitytools.d"

if [[ -n "$WAYLAND_DISPLAY" ]]; then
   # Assuming that we only have one SteamVR installed, it will replace only for SteamVR
   echog "Patching steam commandline options to allow proper steamvr launching on wayland."
   if [[ $MULTI_GPU == "1" ]]; then
      sed -iv 's|"LaunchOptions"[[:space:]]*""|"LaunchOptions"         "WAYLAND_DISPLAY='' prime-run %command%"|g' "$HOME/.steam/steam/userdata/80832101/config/localconfig.vdf" ||
         echor "Couldn't patch wayland display variable om steamvr commandline options, you might want to set it manually: WAYLAND_DISPLAY='' prime-run %command%"
   else
      sed -iv 's|"LaunchOptions"[[:space:]]*""|"LaunchOptions"         "WAYLAND_DISPLAY='' %command%"|g' "$HOME/.steam/steam/userdata/80832101/config/localconfig.vdf" ||
         echor "Couldn't patch wayland display variable om steamvr commandline options, you might want to set it manually: WAYLAND_DISPLAY='' %command%"
   fi
fi

echog "Closing steam to apply commandline options and for SteamPlay-None"
pkill steam
sleep 3
pkill -9 steam

echog "Next prompt for superuser access prevents annoying popup from steamvr (yes/no with asking for superuser) that prevents steamvr from launching automatically."
distrobox-host-exec pkexec setcap CAP_SYS_NICE+ep "$HOME/.steam/steam/steamapps/common/SteamVR/bin/linux64/vrcompositor-launcher" ||
   echor "Couldn't setcap vrcompositor, steamvr will ask for permissions every single launch."

echog "Running steamvr once to generate startup files."
steam steam://run/250820 &>/dev/null &
wait_for_initial_steamvr
cleanup_alvr

echog "At this point you can safely add your existing library from your system if you had one."
echog "Also set Steam Play None as compatibility option for SteamVR if you haven't already."
echog "When ready for next step, press enter to continue."
read

export STEP_INDEX=3
sleep 2

echog "Installing alvr, compilation might take a loong time (up to 15-20 minutes or more depending on CPU)."
echog "If during compiling you think it's frozen, don't close it, it's still compiling."
echog "This installation script will download apk client for the headset later, but you shouldn't connect it to alvr during this script installation, leave it to post install."
paru -q --noprogressbar -S rust alvr --noconfirm --assume-installed vulkan-driver --assume-installed lib32-vulkan-driver || exit 1
# clear cache, alvr targets folder might take up to 10 gb
yes | paru -q --noprogressbar -Scc || exit 1
alvr_dashboard &>/dev/null &
echog "ALVR and dashboard now launch. Proceed with setup wizard in Installation tab -> Run setup wizard and after finishing it, continue there."
echog "Setting firewall rules will fail and it's normal, not yet available to do when using this installation method."
echog "If after installation you can't seem to connect headset, then please open 9944 and 9943 ports using your system firewall."
echog "Launch SteamVR using button on left lower corner and after starting steamvr, you should see one headset showing up in steamvr menu and 'Streamer: Connected' in ALVR dashboard."
echor "After you have done with this, press enter here, and don't close alvr dashboard."
read
echog "Downloading ALVR apk, you can install it now from the $prefix folder into your headset using either ADB or Sidequest on your system."
wget -q --show-progress "$ALVR_APK_LINK" || echor "Could not download apk, please download it from $ALVR_APK_LINK manually."

STEP_INDEX=4
sleep 2

# installing wlxoverlay
echog "For using desktop from inside vr instead of broken steamvr overlay, we will install WlxOverlay."
wget -q --show-progress -O "$WLXOVERLAY_FILENAME" "$WLXOVERLAY_LINK"
chmod +x "$WLXOVERLAY_FILENAME"
if [[ -n "$WAYLAND_DISPLAY" ]]; then
   echog "If you're not (on wlroots-based compositor like Sway), it will ask for display to choose. Choose each display individually."
fi
./"$WLXOVERLAY_FILENAME" &>/dev/null &
if [[ -n "$WAYLAND_DISPLAY" ]]; then
   echog "If everything went well, you might see little icon on your desktop that indicates that screenshare is happening (by WlxOverlay) created by xdg portal."
fi
echog "WlxOverlay adds itself to SteamVR auto-startup. No need to start manually."
echog "Press enter to continue."
read

STEP_INDEX=5
sleep 2

# patching steamvr (without it, steamvr might lag to hell)
../patch_bindings_spam.sh "$HOME/.steam/steam/steamapps/common/SteamVR"

cleanup_alvr
cd ..

STEP_INDEX=6
sleep 2

# post messages
echog "From that point on, ALVR should be installed and WlxOverlay should be working. Please refer to https://github.com/galister/WlxOverlay/wiki/Getting-Started to familiarise with controls."
echor "To start alvr now you need to use start-alvr.sh script from this repository. It will also open Steam for you."
echog "In case you want to enter into container, use './open-container.sh' in terminal"
echog "Don't forget to enable Steam Play for all supported titles with latest (non-experimental) proton to make all games visible as playable in Steam."
echog "Thank you for using the script! Continue with installing alvr apk to headset and with very important Post-installation notes to configure ALVR and SteamVR"
