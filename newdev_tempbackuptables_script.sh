## Identify empty tables that are older than 7 days and are not in an exceptions table (where we put tables that are ok to exceed this rule)
#check to make sure all three parameters are entered
if [ $# -ne 3 ]
then
   echo "< 3 parameters <target dbname> <db hostname> <notice email groups>"
   echo "< 3 parameters <target dbname> <db hostname> <notice email groups>" | mailx -r bds-noreply@hp.com -s "Less than 3 parameters used -  $0 <TARGET DBNAME> <DB HOSTNAME> <NOTICE EMAIL GROUPS>" jared.vibert@hpe.com
   exit 1
fi

#set the entered parameters to variables
export DBNAME=$1
export HOSTNM=$2

export VSQL="/opt/vertica/bin/vsql -U srvc_bds_vertica_maint -w Vert.14.Blue -d $DBNAME -h $HOSTNM -P footer=off -p 5433"
EMAIL_FROM="bds-noreply@hp.com"
EMAIL_TO="jared.vibert@hpe.com"
export SCRDIR=/home/srvc_bds_tidal/vertica/mnt_scripts_daily

#get output for whether database is up or not
$VSQL << EOF
\o /tmp/node_status.out
select node_name, node_address, node_state from nodes;
\o
\q
EOF

## validate if database is exist and up running
if [ $? -ne 0 ]
then
   echo "Some error occurred when checking \"select node_name, node_address, node_state from nodes;\". \nIt likely did not complete successfully." | mailx -r bds-noreply@hp.com -s "Not able to connect to DB $2" jared.vibert@hpe.com
   exit 1
fi

export DBNAME=`cat /tmp/node_status.out | grep "^ v_" | head -1 | awk '{print $1}'|cut -d"_" -f2-|rev|cut -d"_" -f2-|rev`

if [ $1 != $DBNAME ]
then
   echo "The db name entered in the command did not match the db name in the \"nodes\" table" | mailx -r bds-noreply@hp.com -s "Not able to connect to DB $2" jared.vibert@hpe.com
   exit 1
fi

ssh vibertj@$HOSTNM << EOF
pbrun su - vertica -c "/opt/vertica/bin/vsql -t -c \"select 'drop table '||table_schema||'.'||table_name||' CASCADE;' from (select distinct table_schema, table_name from tables where ((table_name ilike '%tmp%' or table_name ilike '%temp%' or table_name ilike '%bkp%' or table_name ilike '%backup%') and table_name not ilike '%template%' and table_name not ilike '%bkpf%' and table_name not ilike '%rbkp%') and owner_name <> 'vertica' and create_time <= (current_timestamp - interval '7 days') except select * from dev_automatedrestrictions.tempbackuptable_exceptions)a order by 1;\" | /usr/bin/tee /home/vertica/newdev_tempbackuptables_input.txt"
pbrun su - vertica -c "/bin/sed -i '$d' /home/vertica/newdev_tempbackuptables_input.txt" #remove the last line of the file
pbrun su - vertica -c "/bin/sed -i -e 's/^.//' /home/vertica/newdev_tempbackuptables_input.txt" #remove the random space at the beginning of each line
pbrun su - vertica -c "/opt/vertica/bin/vsql -f /home/vertica/newdev_tempbackuptables_input.txt | /usr/bin/tee /home/vertica/newdev_tempbackuptables_erroroutput.txt" #run the input file as vsql commands and output to a txt file
EOF

rm /tmp/node_status.*

: <<'COMMENT'
create schema dev_automatedrestrictions;
create table dev_automatedrestrictions.tempbackuptable_exceptions(schema_name varchar(128), table_name varchar(128));

insert into dev_automatedrestrictions.tempbackuptable_exceptions values ('schema_name', 'temp');
COMMENT
