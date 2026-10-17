import importlib.machinery
import importlib.util
from pathlib import Path
import sys
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]/'payload/common';sys.path.insert(0,str(ROOT/'common'))
loader=importlib.machinery.SourceFileLoader('docker_perf',str(ROOT/'modules/dockermanager/docker-manager-helper'))
spec=importlib.util.spec_from_loader(loader.name,loader);helper=importlib.util.module_from_spec(spec);loader.exec_module(helper)


class PerformanceTests(unittest.TestCase):
    def test_summary_does_not_wait_for_disk_scan_or_duplicate_version(self):
        with patch.object(helper,'engine_status',return_value={'engineRunning':True}),patch.object(helper,'json_output',return_value={'ServerVersion':'28.0.0'}) as api,patch.object(helper,'image_ids',return_value=[]),patch.object(helper,'docker') as docker:
            self.assertEqual(helper.system_summary({})['serverVersion'],'28.0.0')
        self.assertEqual(api.call_count,1);docker.assert_not_called()

    def test_disk_cache_and_force_refresh(self):
        cache={'time':time.time(),'socket':17,'disk':[{'Type':'Images','Size':'1GB'}]}
        with patch.object(helper.os,'stat',return_value=SimpleNamespace(st_ino=17)),patch.object(helper.user_state_io,'read_state',return_value=cache),patch.object(helper.user_state_io,'write_state') as write,patch.object(helper,'docker',return_value=SimpleNamespace(stdout='{"Type":"Images"}')) as docker:
            self.assertEqual(helper.system_disk({})['disk'],cache['disk']);docker.assert_not_called()
            helper.system_disk({'force':True});self.assertEqual(docker.call_count,1);write.assert_called_once()


if __name__=='__main__':unittest.main()
