cat <<EOF |tee aws_route53_delete.py
import boto3

route53 = boto3.client('route53')

def list_hosted_zones():
    """
    列出所有托管区域
    """
    hosted_zones = []
    response = route53.list_hosted_zones()
    hosted_zones.extend(response['HostedZones'])

    while 'NextMarker' in response:
        response = route53.list_hosted_zones(Marker=response['NextMarker'])
        hosted_zones.extend(response['HostedZones'])

    return hosted_zones

def delete_resource_record_sets(hosted_zone_id):
    """
    删除指定托管区域下的所有解析记录
    """
    response = route53.list_resource_record_sets(HostedZoneId=hosted_zone_id)
    resource_record_sets = response['ResourceRecordSets']

    while 'NextRecordName' in response:
        response = route53.list_resource_record_sets(
            HostedZoneId=hosted_zone_id,
            StartRecordName=response['NextRecordName'],
            StartRecordType=response['NextRecordType']
        )
        resource_record_sets.extend(response['ResourceRecordSets'])

    for record in resource_record_sets:
        if record['Type'] != 'NS' and record['Type'] != 'SOA':
            route53.change_resource_record_sets(
                HostedZoneId=hosted_zone_id,
                ChangeBatch={
                    'Changes': [
                        {
                            'Action': 'DELETE',
                            'ResourceRecordSet': record
                        }
                    ]
                }
            )

def delete_hosted_zone(hosted_zone_id):
    """
    删除指定的托管区域
    """
    route53.delete_hosted_zone(Id=hosted_zone_id)

if __name__ == '__main__':
    hosted_zones = list_hosted_zones()
    for hosted_zone in hosted_zones:
        hosted_zone_id = hosted_zone['Id']
        print(f"Processing hosted zone: {hosted_zone_id}")
        delete_resource_record_sets(hosted_zone_id)
        delete_hosted_zone(hosted_zone_id)

EOF


python aws_route53_delete.py