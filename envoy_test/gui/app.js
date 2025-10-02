const express = require('express');
const app = express();
app.get('/',(_,res)=>res.send('Hello from GUI'));
app.listen(8000,()=>console.log('GUI listening on 8000'));
