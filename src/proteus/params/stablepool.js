const ms = [
    0.07494935204566536, 
    0.17643751050180143, 
    0.2949495438339487, 
    0.43999856454985486, 
    0.6216382043914934, 
    0.8556912637428409, 
    1.1687175329956858, 
    1.608897159648329, 
    2.273239856423753, 
    3.3913456148879795, 
    5.669326477431938, 
    12.347344823599833
]

const _as = [
    -12.31124210770099, 
    0.9917035839248023, 
    0.9906450076233401, 
    0.999011810446015, 
    0.9993735330997867, 
    0.9985525060441984, 
    0.9987405274363584, 
    0.9986725175767023, 
    0.9990272161015132, 
    0.9990948735958349, 
    0.9975890937964287, 
    0.9865003931494054, 
    0.0
]

const bs = [
    0.0, 
    0.9970471598860288, 
    0.9968603873187225, 
    0.9993281719946191, 
    0.9994873294430439, 
    0.9989769476584511, 
    0.9991378359211192, 
    0.9990583516057224, 
    0.9996290250548222, 
    0.9997828267675003, 
    0.9946762070477967, 
    0.9318107428693113, 
    -11.2488497799632
]

const ks = [
    1.0, 
    1271.662369279242, 
    1144.930865908983, 
    8617.266801448794, 
    12557.49018886828, 
    5790.114737139857, 
    6742.3108135256125, 
    6304.073883970292, 
    10644.662117674987, 
    12744.542018026727, 
    1849.8189707408649, 
    175.1819810878204, 
    1.0808453401280465
]

const feePercent = 0.025

module.exports = { ms, _as, bs, ks, feePercent }