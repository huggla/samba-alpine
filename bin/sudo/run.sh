#!/bin/sh
set -e

environment="/etc/samba/environment"
var(){
   section_matches="$(awk -v section=$1 -F_ '$1==section{print $2}' $environment)"
   return "$(echo $section_matches | awk -v param=$2 -F= '$1==param{print $2}')"
}
var "global" "smb_passwd_file"
exit
if [ -e "$environment" ]
then
   IFS="${IFS};"
   global_smb_passwd_file="$(awk -F= '$1=="global_smb_passwd_file"{print $2;exit}' environment)"
   smbpasswd_file="$(dirname "$global_smb_passwd_file")"
   mkdir -p "$smbpasswd_file"
   chmod u=rwx,go= "$smbpasswd_file"
   touch "$global_smb_passwd_file"
   chmod u=rwx,go= "$global_smb_passwd_file"
   echo "smbpasswd:$global_smb_passwd_file" >> "$environment"
   CONFIG_FILE="$(awk -F= '$1=="CONFIG_FILE"{print $2;exit}' environment)"
   if [ ! -s "$CONFIG_FILE" ]
   then
      SHARES="global;$SHARES"
      for share in $SHARES
      do
         echo >> "$CONFIG_FILE"
         echo "[$share]" >> "$CONFIG_FILE"
         share_lc="$(echo $share | xargs | tr '[:upper:]' '[:lower:]')"
         share_parameters=`env | /bin/grep "${share_lc}_" | /bin/sed "s/^${share_lc}_//g" | /bin/grep -oE '^[^=]+'`
         path_value="$SHARES_DIR/$share"
         for param in $share_parameters
         do
            param_var="${share_lc}_${param}"
            eval "param_value=\$$param_var"
            if [ -n "$param_value" ]
            then
               if [ "$param" == "path" ]
               then
                  path_value=$param_value
               else
                  echo -n "$param" | tr '_' ' ' >> "$CONFIG_FILE"
                  echo "=$param_value" >> "$CONFIG_FILE"
               fi
            fi
         done
         env -i $sudo "$SUDO_DIR/mkdir2root" "$path_value"
         echo "path=$path_value" >> "$CONFIG_FILE"
      done
   fi
   env -i $sudo "$SUDO_DIR/addlinuxusers" $SHARE_USERS
   if [ ! -s "$global_smb_passwd_file" ]
   then
      for user in $SHARE_USERS
      do
         user_lc=$(echo $user | xargs | tr '[:upper:]' '[:lower:]')
         envvar="password_file_$user_lc"
         eval "userpwfile=\$$envvar"
         if [ -z "$userpwfile" ]
         then
            envvar="password_$user_lc"
            eval "user_pw=\$$envvar"
            if [ -n "$user_pw" ]
            then
               userpwfile=$CONFIG_DIR/$user"_pw"
               echo $user_pw > $userpwfile
               unset user_pw
               unset $envvar
            else
               echo "No password given for $user."
               exit 1
            fi
         fi
         env -i $sudo "$SUDO_DIR/chown2root" "$userpwfile"
         env -i $sudo "$SUDO_DIR/addshareuser" "$user" "$userpwfile" "$SMBUSERS_FILE" $DELETE_PASSWORD_FILES
      done
   fi
   if [ -n "$global_username_map" ] 
   then
      if [ ! -e "$global_username_map" ]
      then
         username_dir="$(dirname "$global_username_map")"
         if [ ! -e "$username_dir" ]
         then
            /bin/mkdir -p "$username_dir"
         fi
         >"$global_username_map"
         for user in $USERNAME_MAP
         do
            echo "$user" >> "$global_username_map"
         done
      fi
      env -i $sudo "$SUDO_DIR/chown2root" "$global_username_map"
   fi
   env -i $sudo "$SUDO_DIR/chown2root" "$CONFIG_DIR"
   env -i $sudo "$SUDO_DIR/chown2root" "$SHARES_DIR"
fi
exec env -i "$BIN_DIR/runsmbd" "$SUDO_DIR"
exit 0
