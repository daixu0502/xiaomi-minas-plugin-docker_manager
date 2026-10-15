import importlib.machinery
import importlib.util
import os
from pathlib import Path
import pwd
import sys
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace
import stat

COMMON=Path(__file__).resolve().parents[1]/'payload/common'
sys.path.insert(0,str(COMMON))
import user_state_io as state


class UserStateTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        self.home=self.root/'u123/plugin/dockermanager'
        self.home.mkdir(parents=True)
        self.uid=os.getuid();self.account=pwd.getpwuid(self.uid)
        if self.uid==0:self.skipTest('Run unprivileged; deployment also checks real NAS uid ownership')
        for target,value in [('HOME_ROOT',self.root)]:
            p=patch.object(state,target,value);p.start();self.addCleanup(p.stop)
        p=patch.object(state.pwd,'getpwnam',return_value=self.account);p.start();self.addCleanup(p.stop)

    def test_state_is_inside_plugin_var_and_owned_by_ordinary_user(self):
        state.write_state('u123','dockermanager','status.json',{'state':'done'})
        target=self.home/'var/status.json'
        self.assertEqual(target.stat().st_uid,self.uid)
        self.assertEqual(target.stat().st_mode&0o777,0o600)
        self.assertEqual(state.read_state('u123','dockermanager','status.json'),{'state':'done'})
        self.assertFalse(list(self.home.rglob('.state-*')))

    def test_lock_excludes_another_process_then_releases(self):
        with state.state_lock('u123','dockermanager','test.lock') as first:
            self.assertTrue(first)
            with state.state_lock('u123','dockermanager','test.lock') as second:self.assertFalse(second)
        with state.state_lock('u123','dockermanager','test.lock') as third:self.assertTrue(third)

    def test_symlink_state_directory_does_not_redirect_writes(self):
        outside=self.root/'outside';outside.mkdir()
        (self.home/'var').symlink_to(outside,target_is_directory=True)
        with self.assertRaises(ValueError):state.write_state('u123','dockermanager','status.json',{'x':1})
        self.assertFalse(list(outside.iterdir()))

    def test_symlink_file_cannot_expose_or_overwrite_other_files(self):
        outside=self.root/'outside.json';outside.write_text('{"private":"fixture"}')
        (self.home/'var').mkdir();(self.home/'var/status.json').symlink_to(outside)
        for operation in ('read','write'):
            with self.assertRaises(ValueError):
                if operation=='read':state.read_state('u123','dockermanager','status.json')
                else:state.write_state('u123','dockermanager','status.json',{'x':1})
        self.assertEqual(outside.read_text(),'{"private":"fixture"}')

    def test_fifo_is_rejected_without_blocking(self):
        (self.home/'var').mkdir();os.mkfifo(self.home/'var/status.json')
        self.assertIsNone(state.read_state('u123','dockermanager','status.json'))

    def test_invalid_identity_or_path_is_rejected(self):
        for user,plugin,name in [('root','dockermanager','x'),('u123','sshrecovery','x'),('u123','dockermanager','../x')]:
            with self.assertRaises(ValueError):state.read_state(user,plugin,name)

    def test_legacy_status_migration_preserves_existing_user_state(self):
        spec=importlib.util.spec_from_file_location('layout_admin',COMMON/'component_admin.py')
        admin=importlib.util.module_from_spec(spec);spec.loader.exec_module(admin)
        old=self.root/'legacy.json';old.write_text('{"state":"done","taskId":"old"}')
        class LegacyFile:
            name='dockermanager-upgrade-status.json'
            def exists(self):return old.exists()
            def lstat(self):return SimpleNamespace(st_mode=stat.S_IFREG|0o600,st_uid=0)
            def read_bytes(self):return old.read_bytes()
            def unlink(self):old.unlink()
        legacy=LegacyFile()
        real_path=Path
        def route(value):
            if value=='/run/dockermanager-upgrade-status.json':return legacy
            if value=='/run/dockermanager-bulk-status.json':return self.root/'missing'
            return real_path(value)
        backup=self.root/'backup';backup.mkdir()
        data={'users':{'u123':['dockermanager']}}
        with patch.object(admin,'Path',side_effect=route),patch.object(admin,'atomic',side_effect=lambda p,data,*args:p.write_bytes(data)):
            admin.migrate_docker_status(data,backup)
            self.assertEqual(state.read_state('u123','dockermanager','docker-upgrade-status.json')['taskId'],'old')
            self.assertFalse(old.exists())
            state.write_state('u123','dockermanager','docker-upgrade-status.json',{'state':'done','taskId':'new'})
            old.write_text('{"state":"done","taskId":"old"}')
            admin.migrate_docker_status(data,backup)
            self.assertEqual(state.read_state('u123','dockermanager','docker-upgrade-status.json')['taskId'],'new')


class DockerStatusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        loader=importlib.machinery.SourceFileLoader('layout_docker',str(COMMON/'docker-manager-helper'))
        spec=importlib.util.spec_from_loader(loader.name,loader);cls.module=importlib.util.module_from_spec(spec);loader.exec_module(cls.module)

    def test_reboot_makes_old_running_status_interrupted(self):
        for method in ('read_upgrade_status','read_bulk_status'):
            with patch.object(self.module.user_state_io,'read_state',return_value={'state':'running','bootId':'previous-boot','pid':123}):
                result=getattr(self.module,method)()
            self.assertEqual(result['state'],'error');self.assertIsNone(result['pid'])

    def test_caller_cannot_select_another_users_state(self):
        with patch.dict(os.environ,{'SUDO_USER':'u123'}):
            with self.assertRaises(self.module.ApiError):self.module.dispatch({'pluginUser':'u456','action':'system_summary'})


if __name__=='__main__':unittest.main()
