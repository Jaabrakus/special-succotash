"""Read-only importer tests; never execute the catalog/profile writer."""
import unittest
from import_recom_weapons import balanced_block, parse_weapons


class StanceImportTests(unittest.TestCase):
    def test_nested_and_quoted_parentheses(self):
        source = 'STANCE_STAND ( Label ( "x)y" ) Kick ( 12 ) Nested ( V ( 45 ) ) ) Next ( 9 )'
        block = balanced_block(source, "STANCE_STAND")
        self.assertIn('Kick ( 12 )', block)
        self.assertIn('V ( 45 )', block)
        self.assertNotIn('Next', block)
        self.assertEqual(balanced_block(source, "STANCE_PRONE"), "")
        with self.assertRaises(ValueError):
            balanced_block('STANCE_STAND ( Kick ( 12 )', "STANCE_STAND")

    def test_original_weapon_triplets(self):
        weapons = {w['weapon_id']: w for w in parse_weapons({})}
        expected = {'mark_23': (20, 60, 40), 'm4a1': (12, 70, 45),
                    'm60e3': (10, 42, 50), 'ak-47': (10, 26, 31)}
        for name, triplet in expected.items():
            profile = weapons[name]['reticle']
            self.assertEqual(tuple(profile[k] for k in
                ('shot_kick_px', 'shot_kick_return', 'maximum_shot_kick_px')), triplet)


if __name__ == '__main__':
    unittest.main()
