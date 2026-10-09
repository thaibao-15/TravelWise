import os

def fix_file(file_path, replacements):
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    for line_num, new_text in replacements.items():
        if line_num - 1 < len(lines):
            lines[line_num - 1] = new_text + '\n'
            
    with open(file_path, 'w', encoding='utf-8') as f:
        f.writelines(lines)

replacements_1 = {
    21: "      {'id': 'all', 'label': 'Tất cả (4)'},",
    22: "      {'id': 'upcoming', 'label': 'Sắp tới (1)'},",
}
fix_file(r'd:\TravelWise\TravelWise\apps\mobile\lib\features\trips\widgets\overview\trip_search_filter.dart', replacements_1)

print('Done')
