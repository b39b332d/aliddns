# activated inside /etc/config/ddns by setting
#
# option update_script '/usr/lib/ddns/update_sample.sh'
#
# the script is parsed (not executed) inside send_update() function
# of /usr/lib/ddns/dynamic_dns_functions.sh
# so you can use all available functions and global variables inside this script
# already defined in dynamic_dns_updater.sh and dynamic_dns_functions.sh
#
# It make sence to define the update url ONLY inside this script
# because it's anyway unique to the update script
#
# the code here is the copy of the default used inside send_update()
#
[ -z "$domain" ]   && write_log 14 "Service section not configured correctly! Missing 'domain'"
[ -z "$username" ] && write_log 14 "Service section not configured correctly! Missing 'username'"
[ -z "$password" ] && write_log 14 "Service section not configured correctly! Missing 'password'"

local __keyid __keysec __RecordId __RecordIp __RequestId __MSG

[ "${domain:0:2}" == "@." ] && domain="${domain/./}"
[ "$domain" == "${domain/@/}" ] && domain="${domain/./@}"
__HOST="${domain%%@*}"
__DOMAIN="${domain#*@}"


. /usr/share/libubox/jshn.sh
json_init
__MSG=`aliyun configure get -p ddns` || write_log 14 "get configure error!"
if echo $__MSG|grep -q "profile ddns not found!" ;then
	aliyun configure set -p ddns --access-key-id "$username" --access-key-secret "$password" --region "cn-hangzhou" --language en || write_log 14 "set configure error!";
else
	json_load "$__MSG"
	json_get_var __keyid access_key_id
	json_get_var __keysec access_key_secret
	if [ $__keyid != $username ]||[ $__keysec != $password ];then
		aliyun configure set -p ddns --access-key-id "$username" --access-key-secret "$password" --region "cn-hangzhou" --language en;
	fi
fi

__MSG=`/usr/bin/aliyun -p ddns alidns  DescribeDomainRecords --DomainName $__DOMAIN --RRKeyWord $__HOST --Type A` || write_log 14 "get domain record error!" 
json_load "$__MSG"
json_select DomainRecords
json_select Record
json_select 1
json_get_var __RecordId RecordId|| write_log 13 $__MSG
json_get_var __RecordIp Value || write_log 13 $__MSG
[ $__RecordIp == $__IP ] && write_log 7 "aliyun.com answered: no change" && return 0

__MSG=`/usr/bin/aliyun -p ddns alidns UpdateDomainRecord --RR $__HOST --Type  A --Value $__IP --RecordId $__RecordId` || write_log 13 "update domain record error!"
json_load "$__MSG"
json_get_var __RequestId RequestId || write_log 13 $__MSG

write_log 7 "aliyun.com answered:\n$__RequestId"
return 0
