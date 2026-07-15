import pandas as pd
f = r'C:\Users\User\OneDrive\Desktop\fingerprints.xlsx'
df = pd.read_excel(f, sheet_name='in')

print("Rows where Building == '1':")
print(df[df['Building'] == 1][['ReferencePointID','Building','Floor','Room','WifiSSID']].to_string())
print()
print("Building value_counts:")
print(df['Building'].value_counts())
print()
print("Sample of ReferencePointID format:")
print(df['ReferencePointID'].drop_duplicates().head(20).to_string())
