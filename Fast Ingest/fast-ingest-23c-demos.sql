--
-- 23c Fast Ingest New Features Demonstration
-- This assumes a 23c Free database is being used
--
-- Oracle Database 23c Free – Developer Release is the first release of the next-generation
--   Oracle Database, allowing developers a head-start on building applications with 
--   innovative 23c features that simplify development of modern data-driven apps. The 
--   entire feature set of Oracle Database 23c is planned to be generally available within 
--   the next 12 months.
--
--
-- Set up memory areas for the memoptimize write area
connect / as sysdba
set tab off;
set echo on;
--
show parameter large_pool_size;
show parameter memopt:
--
alter system set large_pool_size=512m scope=spfile;
alter system set memoptimize_write_area_size=300M scope=spfile;
shutdown immediate;
startup;
--
show parameter large_pool_size;
show parameter memopt;
--
pause Hit enter ...
--
-- Set up the memopt user for testing
alter session set container=freepdb1;
--
create tablespace memopt_data 
datafile '/opt/oracle/oradata/FREE/FREEPDB1/memopt_data01.dbf'
size 10m autoextend on next 10m;
--
create user memopt identified by memopt
default tablespace memopt_data
quota unlimited on memopt_data;
--
grant connect, resource to memopt;
grant select any table to memopt;
grant select any dictionary to memopt;
grant alter session to memopt;
--
pause Hit enter ...
--
----
-- Fast Ingest Example
----
--
-- Connect to the memopt user and set up a table for memoptimize for write
connect memopt/memopt@freepdb1
set tab off
set echo on
set numwidth 12
--
create table test_fast_ingest (
 id number primary key,
  test_col varchar2(15))
segment creation immediate
memoptimize for write;
--
-- You should see that no memory has been allocated
select * from v$memoptimize_write_area;
--
pause Hit enter ...
--
-- Determine any sequence ids using the memoptimize write verification APIs
select /*+ seqid session rows written to large pool  */ to_number(dbms_memoptimize.GET_WRITE_HWM_SEQID) from dual;
select /*+ seqid rows written to disk  */ to_number(dbms_memoptimize.GET_APPLY_HWM_SEQID) from dual;
--
-- Insert a row using the memoptimize_write hint
insert /*+ memoptimize_write */ into test_fast_ingest values (1,'test1');
-- You may see that no row is returned
select * from test_fast_ingest;
--
-- Insert a few more rows
insert /*+ memoptimize_write */ into test_fast_ingest values (2,'test2');
insert /*+ memoptimize_write */ into test_fast_ingest values (3,'test3');
insert /*+ memoptimize_write */ into test_fast_ingest values (4,'test4');
-- You may still see no rows, depending on how much time has elapsed
select * from test_fast_ingest;
--
pause Hit enter ...
--
-- Explicitly flush the memoptimize write area and let the data be written to disk
exec dbms_memoptimize.write_end;
exec sys.dbms_session.sleep(10);
--
-- Verify that data has been written to the table
select * from test_fast_ingest;
--
-- Verify the sequence ids
select /*+ seqid session rows written to large pool  */ to_number(dbms_memoptimize.GET_WRITE_HWM_SEQID) from dual;
select /*+ seqid rows written to disk  */ to_number(dbms_memoptimize.GET_APPLY_HWM_SEQID) from dual;
--
-- Verify memory allocation in the memoptimize write area
select * from v$memoptimize_write_area;
--
pause Hit enter ...
--
-- Verify memopt session stats to see what work has been performed
col name format a50;
select
  t1.name,
  t2.value
FROM
  v$sysstat t1,
  v$mystat t2
WHERE
  t1.name like 'memopt%'
  AND t1.statistic# = t2.statistic#
  AND t2.value != 0
ORDER BY
  t1.name;
--
pause Hit enter ...
--
----
-- Session level setting - 
-- Avoids the need to specify the memoptimize_write hint
----
--
alter session set memoptimize_writes=on;
--
insert into test_fast_ingest values (5,'test5');
select * from test_fast_ingest;
exec dbms_memoptimize.write_end;
exec sys.dbms_session.sleep(10);
select * from test_fast_ingest;
--
pause Hit enter ...
--
-- Verify memopt session stats to see what work has been performed
col name format a50;
select
  t1.name,
  t2.value
FROM
  v$sysstat t1,
  v$mystat t2
WHERE
  t1.name like 'memopt%'
  AND t1.statistic# = t2.statistic#
  AND t2.value != 0
ORDER BY
  t1.name;
--
pause Hit enter ...
--
----
-- LOB Support
----
--
create table test_SF_fi (
  id number primary key,
  test_col CLOB )
  segment creation immediate
  tablespace MEMOPT_DATA
  LOB(test_col) STORE AS SECUREFILE(
    ENABLE STORAGE IN ROW
    NOCOMPRESS
    CACHE
  )
  memoptimize for write;
--
pause Hit enter ...
--
insert /*+ memoptimize_write */ into test_SF_fi values (1, 'test');
insert /*+ memoptimize_write */ into test_SF_fi values (2, 'test');
select * from test_SF_fi;
exec dbms_memoptimize.write_end;
exec sys.dbms_session.sleep(10);
select * from test_SF_fi;
--
pause Hit enter ...
--
----
-- Parition Support
----
--
create table test_fi_part (
  id number primary key,
  fi_date date,
  test_col varchar2(15))
segment creation immediate
compress
partition by range ( fi_date )
(
  partition part_1992 values less than ( to_date(19930101,'YYYYMMDD') ),
  --
  partition part_1993 values less than ( to_date(19940101,'YYYYMMDD') ),
  --
  partition part_1994 values less than ( to_date(19950101,'YYYYMMDD') ),
  --
  partition part_1995 values less than ( to_date(19960101,'YYYYMMDD') ),
  --
  partition part_1996 values less than ( to_date(19970101,'YYYYMMDD') ),
  --
  partition part_1997 values less than ( to_date(19980101,'YYYYMMDD') ),
  --
  partition part_1998 values less than ( to_date(19990101,'YYYYMMDD') ) 
);
--
-- Enable the part_1998 partition for memoptimize for write
alter table test_fi_part modify partition part_1998 memoptimize for write;
--
pause Hit enter ...
--
-- Insert two rows into the part_1998 partition and verify
insert /*+ memoptimize_write */ into test_fi_part values (1, to_date('19980102','YYYYMMDD'), 'test');
insert /*+ memoptimize_write */ into test_fi_part values (2, to_date('19980102','YYYYMMDD'), 'test');
select * from test_fi_part;
exec dbms_memoptimize.write_end;
exec sys.dbms_session.sleep(10);
select * from test_fi_part;
--
-- You can verify the partition
select * from test_fi_part partition(part_1998);
--
pause Hit enter ...
--
----
-- Encryption Support
---
connect / as sysdba
set tab off
set echo on
--
alter system set wallet_root='/opt/oracle/admin/FREE/wallet' scope=spfile;
shutdown immediate
startup
alter system set tde_configuration="KEYSTORE_CONFIGURATION=FILE" SCOPE=BOTH;
--
HOST mkdir -p /opt/oracle/admin/FREE/wallet
--
pause Hit enter ...
--
-- Create a keystore
ADMINISTER KEY MANAGEMENT CREATE KEYSTORE IDENTIFIED BY myPassword;
--
-- You should see a tde directory listed
HOST ls /opt/oracle/admin/FREE/wallet/
--
-- Open and backup the keystore
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN IDENTIFIED BY myPassword CONTAINER=ALL;
ADMINISTER KEY MANAGEMENT SET KEY IDENTIFIED BY myPassword WITH BACKUP CONTAINER=ALL;
--
-- Verify encryption keys
SET LINESIZE 100
SELECT con_id, key_id FROM v$encryption_keys;
--
-- Verify wallet is open
SET LINESIZE 150
COLUMN wrl_type      FORMAT A10
COLUMN wrl_parameter FORMAT A40
COLUMN status        FORMAT A8
COLUMN wallet_type   FORMAT A12
SELECT * FROM v$encryption_wallet;
--
pause Hit enter ...
--
-- Assumes a wallet and keystore have been setup
--
-- Set up an encrypted tablespace for testing
--
alter session set container=freepdb1;
--
create tablespace encrypted_ts
datafile '/opt/oracle/oradata/FREE/FREEPDB1/encrypted_ts01.dbf'
size 100m autoextend on next 100m
SEGMENT SPACE MANAGEMENT AUTO
encryption using 'AES256'
default storage(encrypt);
--
alter user memopt quota unlimited on encrypted_ts;
--
pause Hit enter ...
--
-- Connect to the memopt user and set up a new table for encryption
connect memopt/memopt@freepdb1
set tab off
set numwidth 12
--
-- Create a table in the encrypted tablespace
create table test_encrypt_fi (
id number primary key,
test_col varchar2(15) )
segment creation immediate
tablespace encrypted_ts
memoptimize for write;
--
pause Hit enter ...
--
-- Insert rows and verify that they have used memoptimized write
insert /*+ memoptimize_write */ into test_encrypt_fi values (1, 'test');
insert /*+ memoptimize_write */ into test_encrypt_fi values (2, 'test');
select count(*) from test_encrypt_fi;
exec dbms_memoptimize.write_end;
exec sys.dbms_session.sleep(10);
select count(*) from test_encrypt_fi;
--
-- Verify memory allocation in the memoptimize write area
select * from v$memoptimize_write_area;
--
pause Hit enter ...
--
-- Verify memopt session stats to see what work has been performed
col name format a50;
select
  t1.name,
  t2.value
FROM
  v$sysstat t1,
  v$mystat t2
WHERE
  t1.name like 'memopt%'
  AND t1.statistic# = t2.statistic#
  AND t2.value != 0
ORDER BY
  t1.name;
--
exit;

