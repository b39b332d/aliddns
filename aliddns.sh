#!/bin/bash

aliddns_ak=""
aliddns_sk=""
aliddns_ttl="600"
if [ ! -n $1 ] ; then
    exit 1
fi
aliddns_name=$1
host_file=/etc/hosts
#for shadowsocks    
if [ `iptables -t nat -L -nv|wc -l` != "14" ];then
	iptables -t nat -D SHADOWSOCKS $((`iptables -t nat -L -nv|wc -l` - 16))
fi
end() {
    if [ `iptables -t nat -L -nv|wc -l` != "14" ];then
        iptables -t nat -A SHADOWSOCKS -p tcp -j REDIRECT --to-ports 12345
    fi
}
#compare
target_ip=`curl -s http://members.3322.org/dyndns/getip`
current_ip=`nslookup $aliddns_name | awk '/^Address/ {print $NF}'| tail -n1`
echo target_ip=$target_ip
echo current_ip=$current_ip
if [ "$target_ip" = "$current_ip" ]
then
    echo "skipping"
    systemctl start shadowsocks-libev
    end
    exit 0
fi 

aliddns_sub=${aliddns_name%.*.*}
aliddns_domain=${aliddns_name##$aliddns_sub'.'}
timestamp=`date -u "+%Y-%m-%dT%H%%3A%M%%3A%SZ"`
urlencode() {
    # urlencode <string>
    out=""
    while read -n1 c
    do
        case $c in
            [a-zA-Z0-9._-]) out="$out$c" ;;
            *) out="$out`printf '%%%02X' "'$c"`" ;;
        esac
    done
    echo -n $out
}

enc() {
    echo -n "$1" | urlencode
}

send_request() {
    local args="AccessKeyId=$aliddns_ak&Action=$1&Format=json&$2&Version=2015-01-09"
    local hash=$(echo -n "GET&%2F&$(enc "$args")" | openssl dgst -sha1 -hmac "$aliddns_sk&" -binary | openssl base64)
    curl -s "http://alidns.aliyuncs.com/?$args&Signature=$(enc "$hash")"
}

get_recordid() {
    grep -Eo '"RecordId":"[0-9]+"' | cut -d':' -f2 | tr -d '"'
}

query_recordid() {
    send_request "DescribeSubDomainRecords" "SignatureMethod=HMAC-SHA1&SignatureNonce=$timestamp&SignatureVersion=1.0&SubDomain=$aliddns_sub.$aliddns_domain&Timestamp=$timestamp"
}

update_record() {
    send_request "UpdateDomainRecord" "RR=$aliddns_sub&RecordId=$1&SignatureMethod=HMAC-SHA1&SignatureNonce=$timestamp&SignatureVersion=1.0&TTL=$aliddns_ttl&Timestamp=$timestamp&Type=A&Value=$target_ip"
}

add_record() {
    send_request "AddDomainRecord&DomainName=$aliddns_domain" "RR=$aliddns_sub&SignatureMethod=HMAC-SHA1&SignatureNonce=$timestamp&SignatureVersion=1.0&TTL=$aliddns_ttl&Timestamp=$timestamp&Type=A&Value=$target_ip"
}


update_hosts() {
    if grep -q "$aliddns_name" "$host_file"; then
        echo "Update record: $record_ip $aliddns_domain"
        sed -i "/$aliddns_name/c $record_ip $aliddns_name" $host_file
    else
        echo "Add record: $target_ip $aliddns_name"
        echo "$target_ip $aliddns_name" >> $host_file
    fi
}

aliddns_record_id=`query_recordid | get_recordid`
if [ "$aliddns_record_id" = "" ]
then
    aliddns_record_id=`add_record | get_recordid`
    echo "added record $aliddns_record_id"
else
    update_record $aliddns_record_id
    echo "updated record $aliddns_record_id"
fi
if [ "$host_file" != "" ]; then
    update_hosts
fi
end 
exit 0
