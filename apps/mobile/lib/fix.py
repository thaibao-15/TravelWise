import re

def fix_file(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Common replacements
    content = content.replace('Ã„Â ang lÃƒÂªn kÃ¡ÂºÂ¿ hoÃ¡ÂºÂ¡ch', 'Đang lên kế hoạch')
    content = content.replace('Ã„Â ÃƒÂ£ qua', 'Đã qua')
    content = content.replace('Ã„Â ÃƒÂ£ hoÃƒÂ n thÃƒÂ nh', 'Đã hoàn thành')
    
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)

fix_file(r'd:\TravelWise\TravelWise\apps\mobile\lib\features\trips\widgets\overview\trip_search_filter.dart')
fix_file(r'd:\TravelWise\TravelWise\apps\mobile\lib\features\trips\widgets\overview\trip_list_card.dart')
print('Fixed files')
