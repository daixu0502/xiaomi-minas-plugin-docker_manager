import importlib.machinery
import importlib.util
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

root = Path(__file__).resolve().parents[1] / 'payload/common'
sys.path.insert(0, str(root))
loader = importlib.machinery.SourceFileLoader('image_helper', str(root/'docker-manager-helper'))
spec = importlib.util.spec_from_loader(loader.name, loader)
helper = importlib.util.module_from_spec(spec)
loader.exec_module(helper)


class ImagesTests(unittest.TestCase):
    def test_deduplicate(self):
        with patch.object(helper, 'docker', return_value=SimpleNamespace(stdout='sha256:a\nsha256:a\nsha256:b\n')) as command:
            self.assertEqual(helper.image_ids(), ['sha256:a', 'sha256:b'])
            self.assertEqual(command.call_args[0][0], ['image', 'ls', '-q', '--no-trunc'])

    def listing(self, include=False):
        regular = ['sha256:tagged', 'sha256:untagged-leaf']
        all_ids = regular + ['sha256:parent']
        rows = [{'Id':ident,'RepoTags':['repo:v1','repo:latest'] if ident==regular[0] else []} for ident in (all_ids if include else regular)]
        with patch.object(helper, 'image_ids', side_effect=lambda all=False: all_ids if all else regular), patch.object(helper,'json_output', return_value=rows) as inspect:
            result = helper.image_list({'includeIntermediate':include})
            self.assertEqual(inspect.call_args[0][0], ['image','inspect']+(all_ids if include else regular))
            return result

    def test_default_includes_untagged_leaf(self):
        result=self.listing()
        self.assertEqual(len(result['images']),2)
        self.assertEqual(result['regularCount'],2)
        self.assertFalse(any(i['intermediate'] for i in result['images']))

    def test_all_labels_only_parents(self):
        result=self.listing(True)
        self.assertEqual(result['intermediateCount'],1)
        self.assertEqual([i['fullId'] for i in result['images'] if i['intermediate']], ['sha256:parent'])

    def test_empty(self):
        with patch.object(helper,'image_ids',return_value=[]),patch.object(helper,'json_output') as inspect:
            self.assertEqual(helper.image_list({})['images'],[])
            inspect.assert_not_called()

    def test_invalid_flag(self):
        for value in ('false', 'true', 0, 1, None):
            with self.assertRaises(helper.ApiError):helper.image_list({'includeIntermediate':value})

    def test_summary_uses_default_count(self):
        with patch.object(helper,'engine_status',return_value={'engineRunning':True}),patch.object(helper,'json_output',side_effect=[{'Images':14},{}]),patch.object(helper,'docker',return_value=SimpleNamespace(returncode=0,stdout='')),patch.object(helper,'image_ids',return_value=list(range(9))):
            self.assertEqual(helper.system_summary({})['images'],9)

    def test_stopped_summary(self):
        with patch.object(helper,'engine_status',return_value={'engineRunning':False}),patch.object(helper,'image_ids') as listing:
            self.assertEqual(helper.system_summary({})['images'],0);listing.assert_not_called()


if __name__=='__main__':unittest.main()
