import model.debug_comparison as dc
p='vivado_project\\CNN.sim\\sim_1\\behav\\xsim\\cnn_intermediate_debug.txt'
parsed=dc.parse_vivado_log_file(p,bits=16)
outs=parsed.get('outputs',[])
from collections import Counter
layers=[o.get('layer','<none>') for o in outs]
print('Total VHDL output blocks parsed:', len(outs))
print('Layer types counts:')
print(Counter(layers))
print('\nSample 10 blocks:')
for i,o in enumerate(outs[:10]):
    print(i, 'layer=', o.get('layer'), 'row=', o.get('row'), 'col=', o.get('col'), 'filters=', list(o.get('filters').keys())[:8])
